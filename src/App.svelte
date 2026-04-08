<svelte:head>
  <title>VersoLibre</title>
  <meta name="description" content="Comunidad poetica con feed, perfiles y acceso para publicar." />
</svelte:head>

<script>
  import { onMount } from "svelte";
  import { isSupabaseConfigured, supabase } from "./lib/supabase.js";

  const ADMIN_EMAIL = "padillajosueezequiel@gmail.com";
  const FEED_BATCH = 6;
  const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
  const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;
  const routes = new Set(["/", "/poemas", "/publicar", "/login", "/registro", "/reset-password", "/perfil", "/autor", "/configuracion", "/admin"]);
  const CATEGORY_OPTIONS = [
    { id: "amor", label: "Amor", aliases: ["romance", "romantico", "deseo", "pareja", "corazon"] },
    { id: "nostalgia", label: "Nostalgia", aliases: ["memoria", "recuerdo", "ausencia", "melancolia"] },
    { id: "esperanza", label: "Esperanza", aliases: ["fe", "luz", "renacer", "calma"] },
    { id: "naturaleza", label: "Naturaleza", aliases: ["lluvia", "mar", "bosque", "rio", "flor"] },
    { id: "ciudad", label: "Ciudad", aliases: ["barrio", "calle", "ruido", "trafico", "urbano"] },
    { id: "infancia", label: "Infancia", aliases: ["hogar", "familia", "juego", "patio"] },
    { id: "duelo", label: "Duelo", aliases: ["perdida", "dolor", "adios", "silencio"] },
    { id: "libre", label: "Libre", aliases: ["experimental", "otros", "sin tema", "mixto"] }
  ];

  let users = [];
  let poems = [];
  let reactions = [];
  let comments = [];
  let authUser = null;
  let authSession = null;
  let sessionUserId = "";
  let currentPath = "/";
  let visibleCount = FEED_BATCH;
  let searchQuery = "";
  let selectedCategory = "all";
  let categorySearch = "";
  let announcement = "";

  let loginEmail = "";
  let loginPassword = "";
  let loginMessage = "";

  let registerName = "";
  let registerUsername = "";
  let registerEmail = "";
  let registerPassword = "";
  let registerBio = "";
  let registerMessage = "";

  let poemTitle = "";
  let poemCategory = "";
  let poemContent = "";
  let publishCategoryOpen = false;
  let publishMessage = "";
  let mobileMenuOpen = false;
  let settingsLoadedUserId = "";
  let profileSettingsMessage = "";
  let privacySettingsMessage = "";
  let passwordMessage = "";
  let bioExpanded = false;
  let settingsName = "";
  let settingsUsername = "";
  let settingsBio = "";
  let settingsEmailVisibility = "private";
  let settingsProfileVisibility = "public";
  let settingsCommentPermissions = "registered";
  let settingsSensitiveFilter = true;
  let currentPassword = "";
  let newPassword = "";
  let confirmPassword = "";
  let resetNewPassword = "";
  let resetConfirmPassword = "";
  let resetPasswordMessage = "";
  let profilePhotoInput;
  let activePoemId = "";
  let activePoemComment = "";
  let activePoemCommentsVisible = 10;
  let viewedProfileId = "";

  function mapProfile(row) {
    return {
      id: row.id,
      email: row.email || "",
      name: row.name || "Autor",
      username: row.username || "usuario",
      bio: row.bio || "Sin biografia por ahora.",
      role: row.role || "user",
      profileVisibility: row.profile_visibility || "public",
      emailVisibility: row.email_visibility || "private",
      commentPermissions: row.comment_permissions || "registered",
      sensitiveFilter: row.sensitive_filter ?? true,
      profileImage: row.profile_image || "",
      joinedAt: row.created_at || new Date().toISOString()
    };
  }

  function mapPoem(row, profileById) {
    const category = findCategoryOption(row.category_id || row.category_label);
    return {
      id: row.id,
      ownerId: row.owner_id,
      title: row.title,
      author: row.author_name || profileById.get(row.owner_id)?.name || "Autor",
      category: row.category_label || category.label,
      categoryId: row.category_id || category.id,
      content: String(row.content || "").replace(/\\n/g, "\n"),
      status: row.status || "published",
      createdAt: row.created_at || new Date().toISOString()
    };
  }

  async function ensureProfile(authUser) {
    if (!isSupabaseConfigured || !supabase || !authUser) return;

    const meta = authUser.user_metadata || {};
    const email = authUser.email || "";
    const fallbackName = meta.name || email.split("@")[0] || "Autor";
    const rawUsername = (meta.username || fallbackName).toLowerCase().replace(/\s+/g, "");
    const safeUsername = rawUsername.replace(/[^a-z0-9._-]/g, "").slice(0, 18) || "user";
    const username = `${safeUsername}${String(authUser.id).slice(-4)}`.slice(0, 24);

    const { data: existing } = await supabase.from("profiles").select("id").eq("id", authUser.id).maybeSingle();
    if (!existing) {
      await supabase.from("profiles").insert({
        id: authUser.id,
        email,
        name: fallbackName,
        username,
        bio: meta.bio || "Nueva voz en VersoLibre.",
        role: email.toLowerCase() === ADMIN_EMAIL ? "admin" : "user",
        profile_visibility: "public",
        email_visibility: "private",
        comment_permissions: "registered",
        sensitive_filter: true,
        profile_image: ""
      });
    } else {
      await supabase.from("profiles").update({ email }).eq("id", authUser.id);
      if (email.toLowerCase() === ADMIN_EMAIL) {
        await supabase.from("profiles").update({ role: "admin" }).eq("id", authUser.id);
      }
    }
  }

  async function refreshData() {
    if (!isSupabaseConfigured || !supabase) return;

    const profilesRes = await fetchProfilesNoCache();
    const poemsRes = await supabase.from("poems").select("*").order("created_at", { ascending: false });
    const reactionsRes = await supabase.from("reactions").select("*");
    const commentsRes = await supabase.from("comments").select("*").order("created_at", { ascending: false });

    if (profilesRes.error) {
      flash("No pudimos cargar perfiles desde Supabase.");
    } else {
      users = (profilesRes.data || []).map(mapProfile);
    }

    const profileById = new Map(users.map((user) => [user.id, user]));

    if (poemsRes.error) {
      flash("No pudimos cargar poemas desde Supabase.");
    } else {
      poems = (poemsRes.data || []).map((row) => mapPoem(row, profileById));
    }

    if (reactionsRes.error) {
      flash("No pudimos cargar reacciones desde Supabase.");
    } else {
      reactions = (reactionsRes.data || []).map((row) => ({
        poemId: row.poem_id,
        userId: row.user_id,
        value: row.value
      }));
    }

    if (commentsRes.error) {
      flash("No pudimos cargar comentarios desde Supabase.");
    } else {
      comments = (commentsRes.data || []).map((row) => ({
        id: row.id,
        poemId: row.poem_id,
        userId: row.user_id,
        author: row.author_name || profileById.get(row.user_id)?.name || "Autor",
        content: row.content,
        createdAt: row.created_at
      }));
    }
  }

  async function bootstrapState() {
    if (!isSupabaseConfigured || !supabase) {
      announcement = "Configura Supabase para activar autenticacion y base de datos real.";
      return;
    }

    const { data: { session } } = await supabase.auth.getSession();
    authSession = session || null;
    authUser = session?.user || null;
    sessionUserId = authUser?.id || "";
    await refreshData();
  }

  function normalizePath(pathname) {
    const clean = pathname.replace(/\/+$/, "") || "/";
    return routes.has(clean) ? clean : "/404";
  }

  function navigate(path) {
    currentPath = normalizePath(path);
    visibleCount = FEED_BATCH;
    searchQuery = "";
    selectedCategory = "all";
    categorySearch = "";
    mobileMenuOpen = false;
    closePoem();
    if (currentPath !== "/autor") {
      viewedProfileId = "";
    }
    window.history.pushState({}, "", currentPath === "/404" ? "/" : currentPath);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function openAuthorProfile(userId) {
    if (!userId) return;
    if (currentUser?.id === userId) {
      navigate("/perfil");
      return;
    }
    viewedProfileId = userId;
    currentPath = "/autor";
    visibleCount = FEED_BATCH;
    searchQuery = "";
    selectedCategory = "all";
    categorySearch = "";
    mobileMenuOpen = false;
    closePoem();
    window.history.pushState({}, "", `/autor?u=${encodeURIComponent(userId)}`);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function flash(message) {
    announcement = message;
    clearTimeout(flash.timeoutId);
    flash.timeoutId = setTimeout(() => {
      announcement = "";
    }, 2600);
  }

  function formatDate(dateString) {
    return new Intl.DateTimeFormat("es-SV", { day: "numeric", month: "short", year: "numeric" }).format(new Date(dateString));
  }

  function formatRelative(dateString) {
    const minutes = Math.max(1, Math.floor((Date.now() - new Date(dateString).getTime()) / 60000));
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours} h`;
    const days = Math.floor(hours / 24);
    if (days < 30) return `${days} d`;
    return formatDate(dateString);
  }

  function formatJoinDate(dateString) {
    return new Intl.DateTimeFormat("es-SV", { month: "long", year: "numeric" }).format(new Date(dateString));
  }

  function truncate(text, size = 180) {
    return text.length <= size ? text : `${text.slice(0, size).trim()}...`;
  }

  function toPreviewText(text) {
    return String(text || "").replace(/\s+/g, " ").trim();
  }

  function canViewProfile(user) {
    if (!user) return false;
    if (currentUser?.role === "admin" || currentUser?.id === user.id) return true;

    const visibility = user.profileVisibility || "public";
    if (visibility === "public") return true;
    if (visibility === "registered") return Boolean(currentUser);
    return false;
  }

  function canViewEmail(user) {
    if (!user) return false;
    if (currentUser?.role === "admin" || currentUser?.id === user.id) return true;

    const visibility = user.emailVisibility || "private";
    if (visibility === "public") return true;
    if (visibility === "registered") return Boolean(currentUser);
    return false;
  }

  function normalizeText(value) {
    return value
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "");
  }

  function findCategoryOption(value) {
    const normalized = normalizeText(value || "");
    return (
      CATEGORY_OPTIONS.find(
        (option) =>
          normalizeText(option.label) === normalized ||
          option.aliases.some((alias) => normalizeText(alias) === normalized)
      ) || CATEGORY_OPTIONS.find((option) => option.id === "libre")
    );
  }

  function initials(name) {
    return name.split(" ").filter(Boolean).slice(0, 2).map((part) => part[0].toUpperCase()).join("");
  }

  function validEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  function isTransientLockError(error) {
    const message = String(error?.message || "").toLowerCase();
    return message.includes("lock \"") || message.includes("another request stole it");
  }

  async function withLockRetry(operation, attempts = 3, delayMs = 180) {
    let lastError = null;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      let result;
      try {
        result = await operation();
      } catch (error) {
        result = { error };
      }
      if (!result?.error) {
        return result;
      }
      lastError = result.error;
      if (!isTransientLockError(lastError) || attempt === attempts - 1) {
        return result;
      }
      await new Promise((resolve) => setTimeout(resolve, delayMs * (attempt + 1)));
    }
    return { error: lastError };
  }

  async function withTimeout(promise, ms, label) {
    let timeoutId;
    const timeoutPromise = new Promise((_, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(`${label} tardó demasiado. Cierra otras pestañas del sitio y vuelve a intentar.`));
      }, ms);
    });

    try {
      return await Promise.race([promise, timeoutPromise]);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  async function updateCurrentProfileViaRpc(payload, label) {
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return { error: new Error("Falta configurar Supabase en Vercel.") };
    }

    const accessToken = authSession?.access_token;
    if (!accessToken) {
      return { error: new Error("Tu sesion expiró. Inicia sesion de nuevo.") };
    }

    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/update_current_profile`, {
        method: "POST",
        headers: {
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      const data = await response.json().catch(() => null);
      if (!response.ok) {
        const message =
          data?.message ||
          data?.error_description ||
          data?.error ||
          `${label} falló (${response.status}).`;
        return { error: new Error(message) };
      }

      return { data, error: null };
    } catch (error) {
      return { error };
    }
  }

  async function fetchProfilesNoCache() {
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      return { data: null, error: new Error("Falta configurar Supabase en Vercel.") };
    }

    const accessToken = authSession?.access_token;
    // If there is no session yet, fallback to client read.
    if (!accessToken || !sessionUserId) {
      const { data, error } = await supabase.from("profiles").select("*");
      return { data, error };
    }

    try {
      const url = `${SUPABASE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(sessionUserId)}&select=*`;
      const response = await fetch(url, {
        method: "GET",
        cache: "no-store",
        headers: {
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${accessToken}`,
          "Cache-Control": "no-cache, no-store, must-revalidate",
          Pragma: "no-cache"
        }
      });

      const data = await response.json().catch(() => null);
      if (!response.ok) {
        const message = data?.message || data?.error_description || data?.error || "No se pudo cargar perfiles.";
        return { data: null, error: new Error(message) };
      }

      return { data: Array.isArray(data) ? data : [], error: null };
    } catch (error) {
      return { data: null, error };
    }
  }

  async function toggleReaction(poemId, value) {
    if (!currentUser || !supabase) {
      flash("Inicia sesion para reaccionar.");
      navigate("/login");
      return;
    }

    const actorId = currentUser.id;
    const existing = reactions.find((item) => item.poemId === poemId && item.userId === actorId);

    if (!existing) {
      const { error } = await supabase.from("reactions").insert({ poem_id: poemId, user_id: actorId, value });
      if (error) {
        flash("No se pudo guardar tu reaccion.");
        return;
      }
      reactions = [...reactions, { poemId, userId: actorId, value }];
      return;
    }

    if (existing.value === value) {
      const { error } = await supabase.from("reactions").delete().eq("poem_id", poemId).eq("user_id", actorId);
      if (error) {
        flash("No se pudo quitar tu reaccion.");
        return;
      }
      reactions = reactions.filter((item) => !(item.poemId === poemId && item.userId === actorId));
      return;
    }

    const { error } = await supabase.from("reactions").update({ value }).eq("poem_id", poemId).eq("user_id", actorId);
    if (error) {
      flash("No se pudo actualizar tu reaccion.");
      return;
    }
    reactions = reactions.map((item) => (item.poemId === poemId && item.userId === actorId ? { ...item, value } : item));
  }

  function openPoem(poemId) {
    activePoemId = poemId;
    activePoemComment = "";
    activePoemCommentsVisible = 10;
  }

  function closePoem() {
    activePoemId = "";
    activePoemComment = "";
    activePoemCommentsVisible = 10;
  }

  function handleBackdropClick(event) {
    if (event.target === event.currentTarget) {
      closePoem();
    }
  }

  async function addComment(poemId) {
    if (!currentUser || !supabase) {
      flash("Inicia sesion para comentar.");
      navigate("/login");
      return;
    }

    const poem = poems.find((item) => item.id === poemId);
    const poemOwner = users.find((user) => user.id === poem?.ownerId);
    const commentRule = poemOwner?.commentPermissions || "registered";
    if (
      commentRule === "nobody" &&
      currentUser.id !== poem?.ownerId &&
      currentUser.role !== "admin"
    ) {
      flash("Este autor no permite comentarios en esta publicacion.");
      return;
    }

    const content = activePoemComment.trim();
    if (content.length < 2) return;

    const nextComment = {
      poem_id: poemId,
      user_id: currentUser.id,
      author_name: currentUser.name,
      content
    };

    const { data, error } = await supabase.from("comments").insert(nextComment).select("*").single();
    if (error) {
      flash("No se pudo publicar el comentario.");
      return;
    }

    comments = [
      {
        id: data.id,
        poemId: data.poem_id,
        userId: data.user_id,
        author: data.author_name,
        content: data.content,
        createdAt: data.created_at
      },
      ...comments
    ];
    activePoemComment = "";
    activePoemCommentsVisible = Math.max(10, activePoemCommentsVisible);
  }

  function loadMoreComments() {
    activePoemCommentsVisible += 10;
  }

  async function updatePoemStatus(poemId, status) {
    if (currentUser?.role !== "admin" || !supabase) return;
    const { error } = await supabase.from("poems").update({ status }).eq("id", poemId);
    if (error) {
      flash("No se pudo moderar el poema.");
      return;
    }
    poems = poems.map((poem) => (poem.id === poemId ? { ...poem, status } : poem));
    flash(status === "hidden" ? "Poema ocultado." : "Poema restaurado.");
  }

  async function deletePoem(poemId) {
    if (currentUser?.role !== "admin" || !supabase) return;
    const { error } = await supabase.from("poems").delete().eq("id", poemId);
    if (error) {
      flash("No se pudo eliminar el poema.");
      return;
    }
    poems = poems.filter((poem) => poem.id !== poemId);
    reactions = reactions.filter((item) => item.poemId !== poemId);
    comments = comments.filter((item) => item.poemId !== poemId);
    if (activePoemId === poemId) {
      closePoem();
    }
    flash("Poema eliminado.");
  }

  async function handleLogin(event) {
    event.preventDefault();
    if (!supabase) {
      loginMessage = "Falta configurar Supabase.";
      return;
    }

    const email = loginEmail.trim().toLowerCase();
    const password = loginPassword.trim();

    if (!validEmail(email)) {
      loginMessage = "Ingresa un correo valido.";
      return;
    }

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error || !data.user) {
      loginMessage = error?.message || "No pudimos iniciar sesion.";
      return;
    }

    authSession = data.session || authSession;
    authUser = data.user;
    await ensureProfile(data.user);
    sessionUserId = data.user.id;
    await refreshData();

    loginEmail = "";
    loginPassword = "";
    loginMessage = "";
    flash(`Bienvenido, ${data.user.user_metadata?.name || "autor"}.`);
    navigate("/perfil");
  }

  async function handleForgotPassword() {
    if (!supabase) {
      loginMessage = "Falta configurar Supabase.";
      return;
    }

    const email = loginEmail.trim().toLowerCase();
    if (!validEmail(email)) {
      loginMessage = "Escribe tu correo para enviarte el enlace de recuperacion.";
      return;
    }

    const redirectTo = `${window.location.origin}/reset-password`;
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo });
    if (error) {
      loginMessage = error.message || "No pudimos enviar el correo de recuperacion.";
      return;
    }

    loginMessage = "Te enviamos un correo para restablecer tu contrasena.";
    flash("Correo de recuperacion enviado.");
  }

  async function handleRegister(event) {
    event.preventDefault();
    if (!supabase) {
      registerMessage = "Falta configurar Supabase.";
      return;
    }

    const name = registerName.trim();
    const username = registerUsername.trim().toLowerCase();
    const email = registerEmail.trim().toLowerCase();
    const password = registerPassword.trim();
    const bio = registerBio.trim() || "Nueva voz en VersoLibre.";

    if (name.length < 3) return (registerMessage = "Tu nombre debe tener al menos 3 caracteres.");
    if (name.length > 60) return (registerMessage = "Tu nombre no puede superar 60 caracteres.");
    if (username.length < 3 || /\s/.test(username)) return (registerMessage = "El usuario debe tener al menos 3 caracteres y sin espacios.");
    if (username.length > 24) return (registerMessage = "El usuario no puede superar 24 caracteres.");
    if (!validEmail(email)) return (registerMessage = "Ingresa un correo valido.");
    if (password.length < 6) return (registerMessage = "La contrasena debe tener al menos 6 caracteres.");
    if (password.length > 64) return (registerMessage = "La contrasena no puede superar 64 caracteres.");

    const usernameInUse = users.some((user) => user.username.toLowerCase() === username);
    if (usernameInUse) {
      registerMessage = "Ese usuario ya existe.";
      return;
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/login`,
        data: {
          name,
          username,
          bio
        }
      }
    });

    if (error) {
      registerMessage = error.message || "No se pudo crear la cuenta.";
      return;
    }

    if (data.user) {
      await ensureProfile(data.user);
    }
    await refreshData();

    registerName = "";
    registerUsername = "";
    registerEmail = "";
    registerPassword = "";
    registerBio = "";

    if (data.session?.user?.id) {
      sessionUserId = data.session.user.id;
      registerMessage = "";
      flash(`Cuenta creada para ${name}.`);
      navigate("/perfil");
      return;
    }

    registerMessage = "Cuenta creada. Revisa tu correo para verificarla y luego inicia sesion.";
    flash("Te enviamos un correo de verificacion.");
    navigate("/login");
  }

  async function handleResetPassword(event) {
    event.preventDefault();
    if (!supabase) {
      resetPasswordMessage = "Falta configurar Supabase.";
      return;
    }

    const nextPassword = resetNewPassword.trim();
    const confirmedPassword = resetConfirmPassword.trim();

    if (nextPassword.length < 6) {
      resetPasswordMessage = "La nueva contrasena debe tener al menos 6 caracteres.";
      return;
    }

    if (nextPassword.length > 64) {
      resetPasswordMessage = "La nueva contrasena no puede superar 64 caracteres.";
      return;
    }

    if (nextPassword !== confirmedPassword) {
      resetPasswordMessage = "La confirmacion no coincide.";
      return;
    }

    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) {
      resetPasswordMessage = "Abre el enlace de recuperacion desde el correo en este mismo navegador.";
      return;
    }

    const { error } = await supabase.auth.updateUser({ password: nextPassword });
    if (error) {
      resetPasswordMessage = error.message || "No pudimos actualizar tu contrasena.";
      return;
    }

    await supabase.auth.signOut();
    sessionUserId = "";
    resetNewPassword = "";
    resetConfirmPassword = "";
    resetPasswordMessage = "";
    loginMessage = "Contrasena actualizada. Ahora inicia sesion con tu nueva clave.";
    flash("Contrasena actualizada.");
    navigate("/login");
  }

  async function handlePublish(event) {
    event.preventDefault();
    if (!currentUser || !supabase) return (publishMessage = "Necesitas iniciar sesion para publicar.");
    if (poemTitle.trim().length < 3) return (publishMessage = "El titulo debe tener al menos 3 caracteres.");
    if (!poemCategory) return (publishMessage = "Elige una categoria para publicar.");
    if (poemContent.trim().length < 24) return (publishMessage = "El poema necesita un poco mas de cuerpo.");

    const category = CATEGORY_OPTIONS.find((option) => option.id === poemCategory) || CATEGORY_OPTIONS[CATEGORY_OPTIONS.length - 1];
    const payload = {
      owner_id: currentUser.id,
      author_name: currentUser.name,
      title: poemTitle.trim(),
      category_id: category.id,
      category_label: category.label,
      content: poemContent.trim(),
      status: "published"
    };

    const { data, error } = await supabase.from("poems").insert(payload).select("*").single();
    if (error) {
      publishMessage = "No se pudo publicar tu poema.";
      return;
    }

    poems = [mapPoem(data, new Map(users.map((user) => [user.id, user]))), ...poems];
    poemTitle = "";
    poemCategory = "";
    poemContent = "";
    publishCategoryOpen = false;
    publishMessage = "Poema publicado en el feed.";
    flash("Tu poema ya esta visible para la comunidad.");
    navigate("/poemas");
  }

  function selectPublishCategory(categoryId) {
    poemCategory = categoryId;
    publishCategoryOpen = false;
  }

  async function logout() {
    if (!window.confirm("¿Seguro que quieres cerrar sesión?")) {
      return;
    }

    if (supabase) {
      await supabase.auth.signOut();
    }
    authSession = null;
    authUser = null;
    sessionUserId = "";
    mobileMenuOpen = false;
    flash("Sesion cerrada.");
    navigate("/");
  }

  async function saveProfileSettings(event) {
    event.preventDefault();
    console.log("[saveProfileSettings] submit fired", {
      hasCurrentUser: Boolean(currentUser),
      hasSupabase: Boolean(supabase),
      authUserId: authUser?.id || null,
      sessionUserId: sessionUserId || null
    });
    if (!currentUser || !supabase) return;
    profileSettingsMessage = "";

    try {
      const trimmedName = (settingsName || currentUser.name || "").trim();
      const trimmedUsername = (settingsUsername || currentUser.username || "").trim().toLowerCase();
      const trimmedBio = settingsBio.trim();
      console.log("[saveProfileSettings] normalized input", {
        trimmedName,
        trimmedUsername,
        trimmedBio,
        bioLength: trimmedBio.length
      });

      if (trimmedName.length < 3) {
        console.log("[saveProfileSettings] blocked by name validation");
        profileSettingsMessage = "El nombre visible debe tener al menos 3 caracteres.";
        return;
      }

      if (trimmedUsername.length < 3 || /\s/.test(trimmedUsername)) {
        console.log("[saveProfileSettings] blocked by username validation");
        profileSettingsMessage = "El usuario debe tener al menos 3 caracteres y sin espacios.";
        return;
      }

      const usernameInUse = users.some(
        (user) => user.id !== currentUser.id && user.username.toLowerCase() === trimmedUsername
      );

      if (usernameInUse) {
        console.log("[saveProfileSettings] blocked by username collision", { trimmedUsername });
        profileSettingsMessage = "Ese nombre de usuario ya esta en uso.";
        return;
      }

      console.log("[saveProfileSettings] calling rpc update_current_profile", {
        name: trimmedName,
        username: trimmedUsername,
        bioLength: trimmedBio.length
      });

      const { error } = await withTimeout(
        updateCurrentProfileViaRpc(
          {
            p_name: trimmedName,
            p_username: trimmedUsername,
            p_bio: trimmedBio || "Sin biografia por ahora."
          },
          "Guardar perfil"
        ),
        10000,
        "Guardar perfil"
      );

      console.log("[saveProfileSettings] rpc finished", {
        hasError: Boolean(error),
        errorMessage: error?.message || null
      });

      if (error) {
        console.log("[saveProfileSettings] rpc error", error);
        profileSettingsMessage = error.message || "No se pudo guardar la configuracion.";
        return;
      }

      if (authUser) {
        authUser = {
          ...authUser,
          user_metadata: {
            ...(authUser.user_metadata || {}),
            name: trimmedName,
            username: trimmedUsername,
            bio: trimmedBio || "Sin biografia por ahora."
          }
        };
      }

      users = users.map((user) =>
        user.id === currentUser.id
          ? {
              ...user,
              name: trimmedName,
              username: trimmedUsername,
              bio: trimmedBio || "Sin biografia por ahora.",
              emailVisibility: settingsEmailVisibility,
              profileVisibility: settingsProfileVisibility,
              commentPermissions: settingsCommentPermissions,
              sensitiveFilter: settingsSensitiveFilter
            }
          : user
      );

      profileSettingsMessage = "Perfil guardado.";
      console.log("[saveProfileSettings] success");
      flash("Tu cuenta se actualizo correctamente.");

      // Refresh in background; don't fail UX if sync takes too long.
      refreshData()
        .then(() => console.log("[saveProfileSettings] refreshData finished"))
        .catch((refreshError) => console.log("[saveProfileSettings] refreshData error", refreshError));
    } catch (error) {
      console.log("[saveProfileSettings] exception", error);
      profileSettingsMessage = error?.message || "No se pudo guardar la configuracion.";
    }
  }

  async function savePrivacySettings(event) {
    event.preventDefault();
    if (!currentUser || !supabase) return;
    privacySettingsMessage = "";

    try {
      const { error } = await withTimeout(
        updateCurrentProfileViaRpc(
          {
            p_email_visibility: settingsEmailVisibility,
            p_profile_visibility: settingsProfileVisibility,
            p_comment_permissions: settingsCommentPermissions,
            p_sensitive_filter: settingsSensitiveFilter
          },
          "Guardar privacidad"
        ),
        10000,
        "Guardar privacidad"
      );

      if (error) {
        privacySettingsMessage = error.message || "No se pudo guardar la privacidad.";
        return;
      }

      users = users.map((user) =>
        user.id === currentUser.id
          ? {
              ...user,
              emailVisibility: settingsEmailVisibility,
              profileVisibility: settingsProfileVisibility,
              commentPermissions: settingsCommentPermissions,
              sensitiveFilter: settingsSensitiveFilter
            }
          : user
      );

      privacySettingsMessage = "Privacidad guardada.";
      flash("Tu privacidad se actualizo correctamente.");

      refreshData().catch(() => {});
    } catch (error) {
      privacySettingsMessage = error?.message || "No se pudo guardar la privacidad.";
    }
  }

  async function savePasswordSettings(event) {
    event.preventDefault();
    if (!currentUser || !supabase) return;

    const currentUserEmail = currentUser.email?.trim().toLowerCase();
    if (!currentUserEmail) {
      passwordMessage = "No pudimos validar tu correo actual.";
      return;
    }

    const { error: reauthError } = await supabase.auth.signInWithPassword({
      email: currentUserEmail,
      password: currentPassword
    });
    if (reauthError) {
      passwordMessage = reauthError.message || "La contrasena actual no coincide.";
      return;
    }

    if (newPassword.length < 6) {
      passwordMessage = "La nueva contrasena debe tener al menos 6 caracteres.";
      return;
    }

    if (newPassword !== confirmPassword) {
      passwordMessage = "La confirmacion no coincide.";
      return;
    }

    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) {
      passwordMessage = error.message || "No pudimos actualizar tu contrasena.";
      return;
    }

    currentPassword = "";
    newPassword = "";
    confirmPassword = "";
    passwordMessage = "Contrasena actualizada.";
    flash("Tu contrasena se actualizo.");
  }

  function promptProfilePhoto() {
    profilePhotoInput?.click();
  }

  async function handleProfilePhotoChange(event) {
    const file = event.currentTarget?.files?.[0];
    if (!file || !currentUser || !supabase) return;

    if (!file.type.startsWith("image/")) {
      profileSettingsMessage = "Selecciona una imagen valida para la foto de perfil.";
      return;
    }

    const reader = new FileReader();
    reader.onload = async () => {
      try {
        const profileImage = String(reader.result || "");
        const { error } = await withTimeout(
          updateCurrentProfileViaRpc(
            { p_profile_image: profileImage },
            "Guardar foto de perfil"
          ),
          10000,
          "Guardar foto de perfil"
        );

        if (error) {
          profileSettingsMessage = error.message || "No pudimos actualizar tu foto de perfil.";
          return;
        }

        users = users.map((user) =>
          user.id === currentUser.id ? { ...user, profileImage } : user
        );
        profileSettingsMessage = "Foto de perfil actualizada.";
        flash("Tu foto de perfil se actualizo.");
        refreshData().catch(() => {});
      } catch (error) {
        profileSettingsMessage = error?.message || "No pudimos actualizar tu foto de perfil.";
      }
    };
    reader.readAsDataURL(file);

    event.currentTarget.value = "";
  }

  function handleScroll() {
    if (currentPath !== "/poemas") return;
    const nearBottom = window.innerHeight + window.scrollY >= document.body.offsetHeight - 720;
    if (nearBottom && visibleCount < filteredPoems.length) {
      visibleCount = Math.min(visibleCount + FEED_BATCH, filteredPoems.length);
    }
  }

  function handleKeydown(event) {
    if (event.key === "Escape" && activePoemId) {
      closePoem();
    }
  }

  onMount(() => {
    bootstrapState();
    currentPath = normalizePath(window.location.pathname);
    if (currentPath === "/autor") {
      viewedProfileId = new URLSearchParams(window.location.search).get("u") || "";
    }
    const onPopState = () => {
      currentPath = normalizePath(window.location.pathname);
      visibleCount = FEED_BATCH;
      viewedProfileId = currentPath === "/autor" ? new URLSearchParams(window.location.search).get("u") || "" : "";
    };

    let authListener = null;

    if (supabase) {
      const authSubscription = supabase.auth.onAuthStateChange(async (event, session) => {
        const nextUser = session?.user || null;
        authSession = session || null;
        authUser = nextUser;
        sessionUserId = nextUser?.id || "";

        if (event === "PASSWORD_RECOVERY") {
          currentPath = "/reset-password";
          window.history.replaceState({}, "", "/reset-password");
          resetPasswordMessage = "Escribe tu nueva contrasena para recuperar el acceso.";
        }

        // Avoid writing profiles on every token refresh to prevent lock contention
        // while user saves settings.
        const shouldSyncProfile = ["INITIAL_SESSION", "SIGNED_IN", "USER_UPDATED"].includes(event);
        if (shouldSyncProfile) {
          await refreshData();
        }

        if (event === "SIGNED_OUT") {
          users = [];
          poems = [];
          reactions = [];
          comments = [];
        }
      });
      authListener = authSubscription?.data?.subscription || null;

      // Realtime disabled to avoid overlapping auth-token locks while saving settings.
    }

    window.addEventListener("popstate", onPopState);
    window.addEventListener("scroll", handleScroll, { passive: true });
    window.addEventListener("keydown", handleKeydown);
    return () => {
      authListener?.unsubscribe();
      window.removeEventListener("popstate", onPopState);
      window.removeEventListener("scroll", handleScroll);
      window.removeEventListener("keydown", handleKeydown);
    };
  });

  $: currentUser =
    users.find((user) => user.id === sessionUserId) ||
    (authUser
      ? {
          id: authUser.id,
          email: authUser.email || "",
          name: authUser.user_metadata?.name || authUser.email?.split("@")[0] || "Autor",
          username:
            String(authUser.user_metadata?.username || authUser.email?.split("@")[0] || "usuario")
              .toLowerCase()
              .replace(/[^a-z0-9._-]/g, "")
              .slice(0, 24) || "usuario",
          bio: authUser.user_metadata?.bio || "Sin biografia por ahora.",
          role: authUser.email?.toLowerCase() === ADMIN_EMAIL ? "admin" : "user",
          profileVisibility: "public",
          emailVisibility: "private",
          commentPermissions: "registered",
          sensitiveFilter: true,
          profileImage: "",
          joinedAt: authUser.created_at || new Date().toISOString()
        }
      : null);
  $: featuredPoem = poems.find((poem) => poem.status === "published") || null;
  $: moderationPoems = currentUser?.role === "admin" ? poems : [];
  $: visibleCategoryOptions = CATEGORY_OPTIONS.filter((option) => {
    const query = normalizeText(categorySearch);
    return (
      !query ||
      normalizeText(option.label).includes(query) ||
      option.aliases.some((alias) => normalizeText(alias).includes(query))
    );
  });
  $: filteredPoems = poems.filter((poem) => {
    const query = normalizeText(searchQuery.trim());
    const poemCategoryOption = findCategoryOption(poem.categoryId || poem.category);
    const visibleForUser = poem.status === "published" || currentUser?.role === "admin";
    const matchesCategory = selectedCategory === "all" || poem.categoryId === selectedCategory || poemCategoryOption.id === selectedCategory;
    const matchesQuery =
      !query ||
      normalizeText(poem.title).includes(query) ||
      normalizeText(poem.author).includes(query) ||
      normalizeText(poem.category).includes(query) ||
      normalizeText(poem.content).includes(query) ||
      poemCategoryOption.aliases.some((alias) => normalizeText(alias).includes(query));
    return visibleForUser && matchesCategory && matchesQuery;
  });
  $: visiblePoems = filteredPoems.slice(0, visibleCount);
  $: selectedPublishCategoryLabel = CATEGORY_OPTIONS.find((option) => option.id === poemCategory)?.label || "Selecciona una categoria";
  $: totalPoems = poems.length;
  $: totalAuthors = new Set(poems.map((poem) => poem.author.toLowerCase())).size;
  $: totalCategories = CATEGORY_OPTIONS.length;
  $: userPoems = currentUser ? poems.filter((poem) => poem.ownerId === currentUser.id) : [];
  $: viewedProfile = users.find((user) => user.id === viewedProfileId) || null;
  $: viewedProfileVisible = canViewProfile(viewedProfile);
  $: viewedProfileEmailVisible = canViewEmail(viewedProfile);
  $: viewedProfilePoems = viewedProfile
    ? poems.filter(
        (poem) =>
          poem.ownerId === viewedProfile.id && (poem.status === "published" || currentUser?.role === "admin")
      )
    : [];
  $: activePoem = poems.find((poem) => poem.id === activePoemId) || null;
  $: activePoemOwner = activePoem ? users.find((user) => user.id === activePoem.ownerId) || null : null;
  $: currentActorId = currentUser?.id || "";
  $: reactionStatsByPoem = reactions.reduce((acc, item) => {
    if (!acc[item.poemId]) {
      acc[item.poemId] = { likes: 0, dislikes: 0 };
    }
    if (item.value === 1) acc[item.poemId].likes += 1;
    if (item.value === -1) acc[item.poemId].dislikes += 1;
    return acc;
  }, {});
  $: commentCountByPoem = comments.reduce((acc, item) => {
    acc[item.poemId] = (acc[item.poemId] || 0) + 1;
    return acc;
  }, {});
  $: actorReactionByPoem = reactions.reduce((acc, item) => {
    if (item.userId === currentActorId) {
      acc[item.poemId] = item.value;
    }
    return acc;
  }, {});
  $: activePoemStats = activePoem ? reactionStatsByPoem[activePoem.id] || { likes: 0, dislikes: 0 } : { likes: 0, dislikes: 0 };
  $: activePoemComments = activePoem ? comments.filter((item) => item.poemId === activePoem.id) : [];
  $: visibleActivePoemComments = activePoemComments.slice(0, activePoemCommentsVisible);
  $: if (currentUser && settingsLoadedUserId !== currentUser.id) {
    settingsLoadedUserId = currentUser.id;
    settingsName = currentUser.name || "";
    settingsUsername = currentUser.username || "";
    settingsBio = currentUser.bio || "";
    settingsEmailVisibility = currentUser.emailVisibility || "private";
    settingsProfileVisibility = currentUser.profileVisibility || "public";
    settingsCommentPermissions = currentUser.commentPermissions || "registered";
    settingsSensitiveFilter = currentUser.sensitiveFilter ?? true;
    profileSettingsMessage = "";
    privacySettingsMessage = "";
    passwordMessage = "";
    bioExpanded = false;
    currentPassword = "";
    newPassword = "";
    confirmPassword = "";
  }
</script>

<a class="skip-link" href="#main-content">Saltar al contenido</a>

<div class="page-shell">
  <header class="site-header">
    <div class="brand" role="button" tabindex="0" on:click={() => navigate("/")} on:keydown={(event) => event.key === "Enter" && navigate("/")}>
      <span class="brand-mark">
        <img src="/favicon.svg" alt="VersoLibre" />
      </span>
      <div>
        <p class="eyebrow">Comunidad poetica</p>
        <h1>VersoLibre</h1>
      </div>
    </div>

    <p class="mobile-brand-title">VersoLibre</p>

    <nav class="main-nav" aria-label="Principal">
      <a href="/" class:active={currentPath === "/"} on:click|preventDefault={() => navigate("/")}>Inicio</a>
      {#if currentUser}
        <a href="/poemas" class:active={currentPath === "/poemas"} on:click|preventDefault={() => navigate("/poemas")}>Feed</a>
        <a href="/publicar" class:active={currentPath === "/publicar"} on:click|preventDefault={() => navigate("/publicar")}>Publicar</a>
        <a href="/perfil" class:active={currentPath === "/perfil"} on:click|preventDefault={() => navigate("/perfil")}>Perfil</a>
        {#if currentUser.role === "admin"}
          <a href="/admin" class:active={currentPath === "/admin"} on:click|preventDefault={() => navigate("/admin")}>Admin</a>
        {/if}
      {/if}
    </nav>

    <div class="header-actions">
      {#if currentUser}
        <button
          class="ghost-btn mobile-menu-button"
          type="button"
          aria-label="Abrir menú"
          aria-expanded={mobileMenuOpen}
          on:click={() => (mobileMenuOpen = !mobileMenuOpen)}
        >
          ≡
        </button>
        <button class="avatar-chip" type="button" on:click={() => navigate("/perfil")}>
          <span>{initials(currentUser.name)}</span>
          <small>
            @{currentUser.username}
            {#if currentUser.role === "admin"}
              · Admin
            {/if}
          </small>
        </button>
      {:else}
        <a href="/registro" class="primary-btn" on:click|preventDefault={() => navigate("/registro")}>Crear cuenta</a>
      {/if}
    </div>
  </header>

  {#if mobileMenuOpen && currentUser}
    <nav class="mobile-nav-panel" aria-label="Menú móvil">
      <a href="/" class:active={currentPath === "/"} on:click|preventDefault={() => navigate("/")}>Inicio</a>
      <a href="/poemas" class:active={currentPath === "/poemas"} on:click|preventDefault={() => navigate("/poemas")}>Feed</a>
      <a href="/publicar" class:active={currentPath === "/publicar"} on:click|preventDefault={() => navigate("/publicar")}>Publicar</a>
      <a href="/perfil" class:active={currentPath === "/perfil"} on:click|preventDefault={() => navigate("/perfil")}>Perfil</a>
      <a href="/configuracion" class:active={currentPath === "/configuracion"} on:click|preventDefault={() => navigate("/configuracion")}>Configuración</a>
      {#if currentUser.role === "admin"}
        <a href="/admin" class:active={currentPath === "/admin"} on:click|preventDefault={() => navigate("/admin")}>Admin</a>
      {/if}
    </nav>
  {/if}

  {#if announcement}
    <p class="announcement" aria-live="polite">{announcement}</p>
  {/if}

  <main id="main-content">
    {#if currentPath === "/"}
      <section class="hero-panel">
        <div class="hero-copy">
          <p class="badge">Feed literario continuo</p>
          <div class="hero-main">
            <div class="hero-content">
              <h2>Una red para leer, publicar y descubrir poemas con mas orden y mas vida.</h2>
              <p class="hero-text hero-summary">
                Lee voces nuevas, publica tus poemas y explora una comunidad literaria pensada para crecer.
              </p>
            </div>

            <aside class="hero-side" aria-label="Resumen rapido">
              <div class="hero-feature">
                <p class="hero-side-kicker">Poema destacado</p>
                {#if featuredPoem}
                  <h3>{featuredPoem.title}</h3>
                  <p class="hero-side-copy">{truncate(toPreviewText(featuredPoem.content), 140)}</p>
                  <div class="hero-feature-meta">
                    <span>Por {featuredPoem.author}</span>
                    <span>{featuredPoem.category}</span>
                  </div>
                {/if}
              </div>
              <div class="quick-stats side-stats">
                <article><strong>{totalPoems}</strong><span>poemas</span></article>
                <article><strong>{totalAuthors}</strong><span>autores</span></article>
                <article><strong>{totalCategories}</strong><span>temas</span></article>
              </div>
              <div class="hero-actions side-actions">
                <a href="/poemas" class="primary-btn" on:click|preventDefault={() => navigate("/poemas")}>Explorar feed</a>
                <a href="/publicar" class="secondary-btn" on:click|preventDefault={() => navigate("/publicar")}>Publicar poema</a>
              </div>
            </aside>
          </div>
        </div>

      </section>

      <section class="home-preview">
        <div class="section-title">
          <div>
            <p class="eyebrow">Recien publicados</p>
            <h2>Lo que esta leyendo la comunidad</h2>
          </div>
          <a href="/poemas" class="text-link" on:click|preventDefault={() => navigate("/poemas")}>Ver feed completo</a>
        </div>

        <div class="preview-grid">
          {#each poems.slice(0, 4) as poem (poem.id)}
            <article class="feed-card compact">
              <div class="feed-card-top">
                <span class="topic-pill">{poem.category}</span>
                <span class="muted">{formatDate(poem.createdAt)}</span>
              </div>
              <h3>{poem.title}</h3>
              <p class="author-line">Por {poem.author}</p>
              <p class="excerpt">{truncate(toPreviewText(poem.content), 130)}</p>
            </article>
          {/each}
        </div>
      </section>

      <footer class="home-copyright">
        <p>© {new Date().getFullYear()} VersoLibre. Todos los derechos reservados por Josue Ezequiel Padilla Ramirez.</p>
        <div class="home-copyright-links">
          <a href="https://quizerquiel.github.io/" target="_blank" rel="noreferrer">Portafolio</a>
          <a href="mailto:padillajosueezequiel@gmail.com">padillajosueezequiel@gmail.com</a>
          <a class="wa-link" href="https://wa.me/50379234627" target="_blank" rel="noreferrer" aria-label="Contactar por WhatsApp">
            <span class="wa-icon" aria-hidden="true">☎</span>
            WhatsApp
          </a>
          <a href="https://www.linkedin.com/in/ezequielpadilla09/" target="_blank" rel="noreferrer">LinkedIn</a>
        </div>
      </footer>
    {:else if currentPath === "/poemas"}
      <section class="feed-shell">
        <div class="section-title">
          <div>
            <p class="eyebrow">Feed principal</p>
            <h2>Poemas de la comunidad</h2>
          </div>
          <p class="section-copy">Filtra, busca y sigue bajando para cargar mas poemas.</p>
        </div>

        <div class="feed-toolbar">
          <label>
            <span>Buscar</span>
            <input bind:value={searchQuery} type="search" placeholder="Titulo, autor, tema o verso" />
          </label>
          <label>
            <span>Buscar categoria</span>
            <input bind:value={categorySearch} type="search" placeholder="Ej. amor, lluvia, duelo" />
          </label>
          <label>
            <span>Tema</span>
            <select bind:value={selectedCategory}>
              <option value="all">Todos los temas</option>
              {#each visibleCategoryOptions as item}
                <option value={item.id}>{item.label}</option>
              {/each}
            </select>
          </label>
        </div>

        <p class="feed-counter" aria-live="polite">Mostrando {visiblePoems.length} de {filteredPoems.length} poemas</p>

        {#if visiblePoems.length}
          <div class="feed-list">
            {#each visiblePoems as poem (poem.id)}
              <article class="feed-card">
                <div class="feed-card-top">
                  <button class="user-chip author-link-btn" type="button" on:click={() => openAuthorProfile(poem.ownerId)}>
                    <span class="user-avatar">{initials(poem.author)}</span>
                    <div>
                      <strong>{poem.author}</strong>
                      <small>{formatRelative(poem.createdAt)}</small>
                    </div>
                  </button>
                  <div class="card-top-right">
                    <span class="topic-pill">{poem.category}</span>
                    {#if currentUser?.role === "admin" && poem.status === "hidden"}
                      <span class="status-badge">Oculto</span>
                    {/if}
                  </div>
                </div>
                <button class="poem-open-area" type="button" aria-label={`Abrir publicación ${poem.title}`} on:click={() => openPoem(poem.id)}>
                  <h3>{poem.title}</h3>
                  <pre class="poem-body">{poem.content}</pre>
                </button>
                <div class="post-engagement">
                  <button
                    class:active={(actorReactionByPoem[poem.id] || 0) === 1}
                    class="ghost-btn compact-btn reaction-btn"
                    type="button"
                    on:click={() => toggleReaction(poem.id, 1)}
                  >
                    Like {reactionStatsByPoem[poem.id]?.likes || 0}
                  </button>
                  <button
                    class:active={(actorReactionByPoem[poem.id] || 0) === -1}
                    class="ghost-btn compact-btn reaction-btn"
                    type="button"
                    on:click={() => toggleReaction(poem.id, -1)}
                  >
                    Dislike {reactionStatsByPoem[poem.id]?.dislikes || 0}
                  </button>
                  <button class="ghost-btn compact-btn reaction-btn" type="button" on:click={() => openPoem(poem.id)}>
                    Comentarios {commentCountByPoem[poem.id] || 0}
                  </button>
                </div>
                {#if currentUser?.role === "admin"}
                  <div class="admin-actions">
                    {#if poem.status === "published"}
                      <button class="ghost-btn compact-btn" type="button" on:click={() => updatePoemStatus(poem.id, "hidden")}>Ocultar</button>
                    {:else}
                      <button class="ghost-btn compact-btn" type="button" on:click={() => updatePoemStatus(poem.id, "published")}>Restaurar</button>
                    {/if}
                    <button class="danger-btn compact-btn" type="button" on:click={() => deletePoem(poem.id)}>Eliminar</button>
                  </div>
                {/if}
              </article>
            {/each}
          </div>

          <div class:done={visiblePoems.length >= filteredPoems.length} class="load-hint">
            {#if visiblePoems.length < filteredPoems.length}
              Sigue bajando para cargar mas poemas.
            {:else}
              Has llegado al final por ahora.
            {/if}
          </div>
        {:else}
          <div class="empty-panel">
            <h3>No encontramos poemas con ese filtro.</h3>
            <p>Prueba otra busqueda o limpia el tema seleccionado.</p>
          </div>
        {/if}
      </section>
    {:else if currentPath === "/publicar"}
      <section class="page-card">
        <div class="section-title">
          <div>
            <p class="eyebrow">Nueva publicacion</p>
            <h2>Publicar un poema</h2>
          </div>
        </div>

        {#if currentUser}
          <form class="stack-form" on:submit={handlePublish}>
            <label>
              <span>Titulo</span>
              <input bind:value={poemTitle} type="text" maxlength="80" placeholder="Ej. La casa y el eco" required />
            </label>
            <label>
              <span>Tema o emocion</span>
              <div class="custom-select">
                <button
                  class="custom-select-trigger"
                  type="button"
                  aria-haspopup="listbox"
                  aria-expanded={publishCategoryOpen}
                  on:click={() => (publishCategoryOpen = !publishCategoryOpen)}
                >
                  <span>{selectedPublishCategoryLabel}</span>
                  <span class="custom-select-caret">▾</span>
                </button>
                {#if publishCategoryOpen}
                  <div class="custom-select-menu" role="listbox" aria-label="Seleccionar categoria">
                    {#each CATEGORY_OPTIONS as option}
                      <button
                        class:active={poemCategory === option.id}
                        class="custom-select-option"
                        type="button"
                        role="option"
                        aria-selected={poemCategory === option.id}
                        on:click={() => selectPublishCategory(option.id)}
                      >
                        {option.label}
                      </button>
                    {/each}
                  </div>
                {/if}
                <input class="hidden-required-input" value={poemCategory} required readonly />
              </div>
            </label>
            <label>
              <span>Poema</span>
              <textarea bind:value={poemContent} rows="12" placeholder="Escribe aqui tus versos..." required></textarea>
            </label>
            <div class="form-actions">
              <button class="primary-btn" type="submit">Publicar en el feed</button>
              <p class="form-note" aria-live="polite">{publishMessage}</p>
            </div>
          </form>
        {:else}
          <div class="gate-panel">
            <h3>Necesitas una cuenta para publicar.</h3>
            <p>Inicia sesion o crea tu perfil para que cada poema quede ligado a un autor.</p>
            <div class="hero-actions">
              <a href="/login" class="primary-btn" on:click|preventDefault={() => navigate("/login")}>Iniciar sesion</a>
              <a href="/registro" class="secondary-btn" on:click|preventDefault={() => navigate("/registro")}>Crear cuenta</a>
            </div>
          </div>
        {/if}
      </section>
    {:else if currentPath === "/login"}
      <section class="auth-layout login-only">
        <article class="auth-card">
          <p class="eyebrow">Acceso</p>
          <h2>Inicia sesion</h2>
          <form class="stack-form" on:submit={handleLogin}>
            <label>
              <span>Correo</span>
              <input bind:value={loginEmail} type="email" autocomplete="email" required />
            </label>
            <label>
              <span>Contrasena</span>
              <input bind:value={loginPassword} type="password" autocomplete="current-password" required />
            </label>
            <div class="form-actions">
              <button class="primary-btn" type="submit">Entrar</button>
              <p class="form-note" aria-live="polite">{loginMessage}</p>
            </div>
          </form>
          <p class="login-inline-link">
            <button
              type="button"
              class="text-link"
              style="background: none; border: 0; padding: 0; cursor: pointer;"
              on:click={handleForgotPassword}
            >
              Olvidé mi contraseña
            </button>
          </p>
          <p class="login-inline-link">
            <a href="/registro" class="text-link" on:click|preventDefault={() => navigate("/registro")}>Crear una cuenta nueva</a>
          </p>
        </article>
      </section>
    {:else if currentPath === "/reset-password"}
      <section class="auth-layout login-only">
        <article class="auth-card">
          <p class="eyebrow">Recuperación</p>
          <h2>Nueva contraseña</h2>
          <p class="section-copy">Abre el enlace del correo de recuperacion en este mismo navegador y define una clave nueva.</p>
          <form class="stack-form" on:submit={handleResetPassword}>
            <label>
              <span>Nueva contraseña</span>
              <input bind:value={resetNewPassword} type="password" maxlength="64" autocomplete="new-password" required />
            </label>
            <label>
              <span>Confirmar nueva contraseña</span>
              <input bind:value={resetConfirmPassword} type="password" maxlength="64" autocomplete="new-password" required />
            </label>
            <div class="form-actions">
              <button class="primary-btn" type="submit">Actualizar contraseña</button>
              <p class="form-note" aria-live="polite">{resetPasswordMessage}</p>
            </div>
          </form>
          <p class="login-inline-link">
            <a href="/login" class="text-link" on:click|preventDefault={() => navigate("/login")}>Volver a iniciar sesión</a>
          </p>
        </article>
      </section>
    {:else if currentPath === "/registro"}
      <section class="auth-layout login-only">
        <article class="auth-card">
          <p class="eyebrow">Registro</p>
          <h2>Crea tu perfil</h2>
          <p class="section-copy">Tu perfil servira para firmar poemas y ordenar la comunidad.</p>
          <form class="stack-form" on:submit={handleRegister}>
            <label>
              <span>Nombre visible</span>
              <input bind:value={registerName} type="text" maxlength="60" required />
            </label>
            <label>
              <span>Usuario</span>
              <input bind:value={registerUsername} type="text" maxlength="24" required />
            </label>
            <label>
              <span>Correo</span>
              <input bind:value={registerEmail} type="email" maxlength="120" autocomplete="email" required />
            </label>
            <label>
              <span>Contrasena</span>
              <input bind:value={registerPassword} type="password" maxlength="64" autocomplete="new-password" required />
            </label>
            <label>
              <span>Bio</span>
              <textarea bind:value={registerBio} rows="4" maxlength="240" placeholder="Una pequena presentacion."></textarea>
            </label>
            <div class="form-actions">
              <button class="primary-btn" type="submit">Crear cuenta</button>
              <p class="form-note" aria-live="polite">{registerMessage}</p>
            </div>
          </form>
          <p class="login-inline-link">
            <a href="/login" class="text-link" on:click|preventDefault={() => navigate("/login")}>Ya tengo cuenta</a>
          </p>
        </article>
      </section>
    {:else if currentPath === "/perfil"}
      <section class="profile-shell">
        {#if currentUser}
          <aside class="profile-card">
            <input
              bind:this={profilePhotoInput}
              class="hidden-input"
              type="file"
              accept="image/*"
              on:change={handleProfilePhotoChange}
            />
            <button class="profile-avatar profile-avatar-button" type="button" on:click={promptProfilePhoto} aria-label="Cambiar foto de perfil">
              {#if currentUser.profileImage}
                <img src={currentUser.profileImage} alt={`Foto de perfil de ${currentUser.name}`} class="profile-avatar-image" />
              {:else}
                {initials(currentUser.name)}
              {/if}
            </button>
            <button class="text-link profile-photo-link" type="button" on:click={promptProfilePhoto}>Añadir foto de perfil</button>
            <h2>{currentUser.name}</h2>
            <p class="username">@{currentUser.username}</p>
            {#if currentUser.role === "admin"}
              <p class="admin-badge">Administrador</p>
            {/if}
            <div class="bio-block">
              <p class="bio">{bioExpanded ? currentUser.bio : truncate(currentUser.bio, 110)}</p>
              {#if currentUser.bio && currentUser.bio.length > 110}
                <button class="text-link bio-toggle" type="button" on:click={() => (bioExpanded = !bioExpanded)}>
                  {bioExpanded ? "Ver menos" : "Ver más..."}
                </button>
              {/if}
            </div>
            <dl class="profile-stats">
              <div><dt>Miembro desde</dt><dd>{formatJoinDate(currentUser.joinedAt)}</dd></div>
              <div><dt>Poemas publicados</dt><dd>{userPoems.length}</dd></div>
              {#if currentUser.role === "admin"}
                <div><dt>En moderacion</dt><dd>{moderationPoems.filter((poem) => poem.status === "hidden").length}</dd></div>
              {/if}
            </dl>
            <div class="profile-actions">
              <a href="/publicar" class="primary-btn" on:click|preventDefault={() => navigate("/publicar")}>Escribir nuevo poema</a>
              <a href="/configuracion" class="ghost-btn action-btn" on:click|preventDefault={() => navigate("/configuracion")}>Configuración</a>
              <button class="ghost-btn action-btn" type="button" on:click={logout}>Cerrar sesión</button>
            </div>
          </aside>

          <div class="profile-feed">
            <div class="section-title profile-feed-header">
              <div>
                <p class="eyebrow">Tu espacio</p>
                <h2>Tus poemas</h2>
              </div>
              <p class="section-copy">Aqui se reune todo lo que has publicado como @{currentUser.username}.</p>
            </div>

            {#if userPoems.length}
              <div class="feed-list">
                {#each userPoems as poem (poem.id)}
                  <article class="feed-card">
                    <div class="feed-card-top">
                      <span class="topic-pill">{poem.category}</span>
                      <span class="muted">{formatDate(poem.createdAt)}</span>
                    </div>
                    <h3>{poem.title}</h3>
                    <pre class="poem-body">{poem.content}</pre>
                  </article>
                {/each}
              </div>
            {:else}
              <div class="empty-panel">
                <h3>Aun no has publicado poemas.</h3>
                <p>Tu perfil ya esta listo. Lo siguiente es compartir tu primer texto.</p>
              </div>
            {/if}

          </div>
        {:else}
          <div class="gate-panel">
            <h3>Tu perfil aparece cuando inicias sesion.</h3>
            <p>En cuanto entres, esta pagina mostrara tu informacion y tus publicaciones.</p>
            <div class="hero-actions">
              <a href="/login" class="primary-btn" on:click|preventDefault={() => navigate("/login")}>Ir a login</a>
              <a href="/registro" class="secondary-btn" on:click|preventDefault={() => navigate("/registro")}>Crear cuenta</a>
            </div>
          </div>
        {/if}
      </section>
    {:else if currentPath === "/autor"}
      <section class="profile-shell">
        {#if viewedProfile}
          <aside class="profile-card">
            <span class="profile-avatar">
              {#if viewedProfile.profileImage}
                <img src={viewedProfile.profileImage} alt={`Foto de perfil de ${viewedProfile.name}`} class="profile-avatar-image" />
              {:else}
                {initials(viewedProfile.name)}
              {/if}
            </span>
            <h2>{viewedProfile.name}</h2>
            <p class="username">@{viewedProfile.username}</p>
            {#if viewedProfile.role === "admin"}
              <p class="admin-badge">Administrador</p>
            {/if}
            {#if viewedProfileVisible}
              <div class="bio-block">
                <p class="bio">{viewedProfile.bio || "Sin biografía."}</p>
              </div>
              <dl class="profile-stats">
                <div><dt>Miembro desde</dt><dd>{formatJoinDate(viewedProfile.joinedAt)}</dd></div>
                <div><dt>Poemas publicados</dt><dd>{viewedProfilePoems.length}</dd></div>
                <div><dt>Perfil</dt><dd>{viewedProfile.profileVisibility === "private" ? "Privado" : viewedProfile.profileVisibility === "registered" ? "Solo registrados" : "Publico"}</dd></div>
                {#if viewedProfileEmailVisible}
                  <div><dt>Correo</dt><dd>{viewedProfile.email}</dd></div>
                {/if}
              </dl>
            {:else}
              <div class="empty-panel compact-empty">
                <h3>Perfil restringido</h3>
                <p>Este autor configuró su perfil para no mostrar contenido público.</p>
              </div>
            {/if}
          </aside>

          <div class="profile-feed">
            <div class="section-title profile-feed-header">
              <div>
                <p class="eyebrow">Autor</p>
                <h2>Poemas de {viewedProfile.name}</h2>
              </div>
              <p class="section-copy">Vista según privacidad configurada por @{viewedProfile.username}.</p>
            </div>

            {#if viewedProfileVisible}
              {#if viewedProfilePoems.length}
                <div class="feed-list">
                  {#each viewedProfilePoems as poem (poem.id)}
                    <article class="feed-card">
                      <div class="feed-card-top">
                        <div class="card-top-right">
                          <span class="topic-pill">{poem.category}</span>
                        </div>
                        <span class="muted">{formatDate(poem.createdAt)}</span>
                      </div>
                      <button class="poem-open-area" type="button" on:click={() => openPoem(poem.id)}>
                        <h3>{poem.title}</h3>
                        <pre class="poem-body">{truncate(poem.content, 260)}</pre>
                      </button>
                    </article>
                  {/each}
                </div>
              {:else}
                <div class="empty-panel">
                  <h3>Este autor aún no publica poemas.</h3>
                  <p>Cuando publique, aquí aparecerán sus textos visibles.</p>
                </div>
              {/if}
            {:else}
              <div class="gate-panel">
                <h3>No puedes ver este perfil todavía.</h3>
                <p>Su visibilidad está en modo privado o solo para registrados.</p>
              </div>
            {/if}
          </div>
        {:else}
          <div class="empty-panel">
            <h3>Perfil no encontrado.</h3>
            <p>Este autor no existe o ya no está disponible.</p>
          </div>
        {/if}
      </section>
    {:else if currentPath === "/configuracion"}
      <section class="page-card">
        {#if currentUser}
          <section class="settings-panel standalone-settings">
            <div class="section-title">
              <div>
                <div class="settings-kicker">
                  <button
                    class="back-link"
                    type="button"
                    aria-label="Volver al perfil"
                    on:click={() => navigate("/perfil")}
                  >
                    ←
                  </button>
                  <p class="eyebrow">Configuracion</p>
                </div>
                <h2>Tu cuenta</h2>
              </div>
              <p class="section-copy">Ajusta tu perfil, privacidad y seguridad desde un solo lugar.</p>
            </div>

            <div class="settings-grid">
              <form class="settings-card stack-form" on:submit={saveProfileSettings}>
                <h3>Perfil</h3>
                <label>
                  <span>Nombre visible</span>
                  <input bind:value={settingsName} type="text" maxlength="60" required />
                </label>
                <label>
                  <span>Usuario</span>
                  <input bind:value={settingsUsername} type="text" maxlength="24" required />
                </label>
                <label>
                  <span>Biografia</span>
                  <textarea bind:value={settingsBio} rows="4"></textarea>
                </label>
                <button class="primary-btn" type="submit">Guardar perfil</button>
                <p class="form-note" aria-live="polite">{profileSettingsMessage}</p>
              </form>

              <form class="settings-card stack-form" on:submit={savePrivacySettings}>
                <h3>Privacidad</h3>
                <label>
                  <span>Visibilidad del perfil</span>
                  <select bind:value={settingsProfileVisibility}>
                    <option value="public">Publico</option>
                    <option value="registered">Solo registrados</option>
                    <option value="private">Privado</option>
                  </select>
                </label>
                <label>
                  <span>Visibilidad del correo</span>
                  <select bind:value={settingsEmailVisibility}>
                    <option value="private">Oculto</option>
                    <option value="registered">Solo registrados</option>
                    <option value="public">Publico</option>
                  </select>
                </label>
                <label>
                  <span>Quien puede comentar</span>
                  <select bind:value={settingsCommentPermissions}>
                    <option value="registered">Solo usuarios registrados</option>
                    <option value="followers">Solo seguidores</option>
                    <option value="nobody">Nadie</option>
                  </select>
                </label>
                <label class="toggle-row">
                  <input bind:checked={settingsSensitiveFilter} type="checkbox" />
                  <span>Filtrar contenido sensible en tu feed</span>
                </label>
                <button class="primary-btn" type="submit">Guardar privacidad</button>
                <p class="form-note" aria-live="polite">{privacySettingsMessage}</p>
              </form>

              <form class="settings-card stack-form" on:submit={savePasswordSettings}>
                <h3>Seguridad</h3>
                <label>
                  <span>Contrasena actual</span>
                  <input bind:value={currentPassword} type="password" autocomplete="current-password" required />
                </label>
                <label>
                  <span>Nueva contrasena</span>
                  <input bind:value={newPassword} type="password" autocomplete="new-password" required />
                </label>
                <label>
                  <span>Confirmar nueva contrasena</span>
                  <input bind:value={confirmPassword} type="password" autocomplete="new-password" required />
                </label>
                <button class="primary-btn" type="submit">Cambiar contrasena</button>
                <p class="form-note" aria-live="polite">{passwordMessage}</p>
              </form>
            </div>
          </section>
        {:else}
          <div class="gate-panel">
            <h3>Necesitas iniciar sesión para ver tu configuración.</h3>
            <p>Entra con tu cuenta para gestionar perfil, privacidad y seguridad.</p>
          </div>
        {/if}
      </section>
    {:else if currentPath === "/admin"}
      <section class="page-card">
        {#if currentUser?.role === "admin"}
          <div class="admin-panel">
            <div class="section-title">
              <div>
                <p class="eyebrow">Moderacion</p>
                <h2>Panel de administrador</h2>
              </div>
              <p class="section-copy">Puedes ocultar, restaurar o eliminar cualquier poema de la plataforma.</p>
            </div>

            <div class="feed-list">
              {#each moderationPoems as poem (poem.id)}
                <article class="feed-card admin-card">
                  <div class="feed-card-top">
                    <div>
                      <strong>{poem.title}</strong>
                      <p class="author-line">Por {poem.author}</p>
                    </div>
                    <div class="card-top-right">
                      <span class="topic-pill">{poem.category}</span>
                      <span class:status-hidden={poem.status === "hidden"} class="status-badge">
                        {poem.status === "hidden" ? "Oculto" : "Publicado"}
                      </span>
                    </div>
                  </div>
                  <p class="excerpt">{truncate(toPreviewText(poem.content), 140)}</p>
                  <div class="admin-actions">
                    {#if poem.status === "published"}
                      <button class="ghost-btn compact-btn" type="button" on:click={() => updatePoemStatus(poem.id, "hidden")}>Ocultar</button>
                    {:else}
                      <button class="ghost-btn compact-btn" type="button" on:click={() => updatePoemStatus(poem.id, "published")}>Restaurar</button>
                    {/if}
                    <button class="danger-btn compact-btn" type="button" on:click={() => deletePoem(poem.id)}>Eliminar</button>
                  </div>
                </article>
              {/each}
            </div>
          </div>
        {:else}
          <div class="gate-panel">
            <h3>Esta vista es solo para administradores.</h3>
            <p>Si necesitas moderar contenido, entra con una cuenta que tenga permisos de admin.</p>
          </div>
        {/if}
      </section>
    {:else}
      <section class="empty-panel">
        <h2>Pagina no encontrada</h2>
        <p>Volvamos al inicio para seguir explorando la comunidad.</p>
        <a href="/" class="primary-btn" on:click|preventDefault={() => navigate("/")}>Ir al inicio</a>
      </section>
    {/if}

    {#if activePoem}
      <div
        class="post-modal-backdrop"
        role="button"
        tabindex="-1"
        aria-label="Cerrar publicación"
        on:click={handleBackdropClick}
        on:keydown={(event) => event.key === "Escape" && closePoem()}
      >
        <div class="post-modal" role="dialog" aria-modal="true" aria-label={`Publicación ${activePoem.title}`}>
          <header class="post-modal-header">
            <button class="user-chip author-link-btn" type="button" on:click={() => openAuthorProfile(activePoem.ownerId)}>
              <span class="user-avatar">{initials(activePoem.author)}</span>
              <div>
                <strong>@{activePoemOwner?.username || activePoem.author}</strong>
                <small>{formatDate(activePoem.createdAt)}</small>
              </div>
            </button>
            <button class="close-modal-icon" type="button" on:click={closePoem} aria-label="Cerrar publicación">×</button>
          </header>

          <div class="post-modal-content">
            <span class="topic-pill">{activePoem.category}</span>
            <h3>{activePoem.title}</h3>
            <pre class="poem-body modal-poem-body">{activePoem.content}</pre>
            <div class="post-engagement modal-engagement">
              <button
                class:active={(actorReactionByPoem[activePoem.id] || 0) === 1}
                class="ghost-btn compact-btn reaction-btn"
                type="button"
                on:click={() => toggleReaction(activePoem.id, 1)}
              >
                Like {activePoemStats.likes}
              </button>
              <button
                class:active={(actorReactionByPoem[activePoem.id] || 0) === -1}
                class="ghost-btn compact-btn reaction-btn"
                type="button"
                on:click={() => toggleReaction(activePoem.id, -1)}
              >
                Dislike {activePoemStats.dislikes}
              </button>
              <span class="comments-counter">{commentCountByPoem[activePoem.id] || 0} comentarios</span>
            </div>
          </div>

          <section class="post-comments">
            <div class="comments-head">
              <h4>Comentarios</h4>
              <span>Más pertinentes</span>
            </div>
            {#if currentUser}
              <form class="comment-form" on:submit|preventDefault={() => addComment(activePoem.id)}>
                <textarea
                  bind:value={activePoemComment}
                  rows="3"
                  maxlength="420"
                  placeholder="Escribe un comentario..."
                ></textarea>
                <div class="comment-form-actions">
                  <button class="primary-btn" type="submit">Comentar</button>
                </div>
              </form>
            {:else}
              <p class="form-note">Inicia sesion para comentar.</p>
            {/if}

            {#if activePoemComments.length}
              <div class="comment-list">
                {#each visibleActivePoemComments as comment (comment.id)}
                  <article class="comment-item">
                    <header>
                      <button class="comment-author-btn" type="button" on:click={() => openAuthorProfile(comment.userId)}>{comment.author}</button>
                      <small>{formatDate(comment.createdAt)}</small>
                    </header>
                    <p>{comment.content}</p>
                  </article>
                {/each}
              </div>
              {#if activePoemComments.length > visibleActivePoemComments.length}
                <div class="comment-more-wrap">
                  <button class="text-link comment-more-btn" type="button" on:click={loadMoreComments}>
                    Ver más comentarios
                  </button>
                </div>
              {/if}
            {:else}
              <p class="form-note">Aun no hay comentarios. Seamos los primeros.</p>
            {/if}
          </section>
        </div>
      </div>
    {/if}
  </main>
</div>
