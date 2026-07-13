window.MetaSignupBridge = {
  _activeSession: null,

  _waitForFb: function (timeoutMs, onReady, onTimeout) {
    var started = Date.now();
    (function poll() {
      if (window.FB && typeof window.FB.init === "function") {
        onReady();
        return;
      }
      if (Date.now() - started >= timeoutMs) {
        onTimeout();
        return;
      }
      setTimeout(poll, 120);
    })();
  },

  _finishSession: function (session, payload) {
    if (!session || session.finished) {
      return;
    }
    session.finished = true;
    if (session.timeoutId) {
      clearTimeout(session.timeoutId);
    }
    if (session.messageHandler) {
      window.removeEventListener("message", session.messageHandler);
    }
    window[callbackNameSafe(session.callbackName)](payload);
  },

  _tryComplete: function (session) {
    if (!session || session.finished) {
      return;
    }
    var code = session.code || window.__metaSignupLastCode || "";
    var wabaId = session.wabaId || "";
    var phoneNumberId = session.phoneNumberId || "";
    if (!code || !wabaId || !phoneNumberId) {
      return;
    }
    window.MetaSignupBridge._finishSession(session, {
      code: code,
      waba_id: wabaId,
      phone_number_id: phoneNumberId,
      display_phone_number: session.displayPhoneNumber || "",
      granted_scopes: session.grantedScopes || "",
    });
  },

  _parseEmbeddedSignupMessage: function (event) {
    if (!event || !event.origin || !event.origin.endsWith("facebook.com")) {
      return null;
    }
    var raw = event.data;
    if (raw == null) {
      return null;
    }
    var payload = raw;
    if (typeof raw === "string") {
      try {
        payload = JSON.parse(raw);
      } catch (e) {
        return null;
      }
    }
    if (!payload || payload.type !== "WA_EMBEDDED_SIGNUP") {
      return null;
    }
    return payload;
  },

  _coexistenceExtras: function () {
    return {
      setup: {},
      featureType: "whatsapp_business_app_onboarding",
      sessionInfoVersion: "3",
      version: "v3",
    };
  },

  launch: function (appId, configId, coexistence, callbackName, extrasOverride) {
    if (window.MetaSignupBridge._activeSession) {
      window.MetaSignupBridge._finishSession(window.MetaSignupBridge._activeSession, null);
    }

    var session = {
      callbackName: callbackName,
      code: "",
      wabaId: "",
      phoneNumberId: "",
      displayPhoneNumber: "",
      grantedScopes: "",
      finished: false,
      cancelled: false,
      timeoutId: null,
      messageHandler: null,
    };
    window.MetaSignupBridge._activeSession = session;
    window.__metaSignupLastCode = "";

    session.messageHandler = function (event) {
      var payload = window.MetaSignupBridge._parseEmbeddedSignupMessage(event);
      if (!payload) {
        return;
      }
      var data = payload.data || {};
      if (data.waba_id) {
        session.wabaId = String(data.waba_id);
      }
      if (data.phone_number_id) {
        session.phoneNumberId = String(data.phone_number_id);
      }
      if (data.display_phone_number) {
        session.displayPhoneNumber = String(data.display_phone_number);
      }
      window.MetaSignupBridge._tryComplete(session);
    };
    window.addEventListener("message", session.messageHandler);

    session.timeoutId = setTimeout(function () {
      if (session.finished) {
        return;
      }
      window.MetaSignupBridge._finishSession(session, null);
    }, 300000);

    window.MetaSignupBridge._waitForFb(
      20000,
      function () {
        window.FB.init({
          appId: appId,
          cookie: true,
          xfbml: false,
          version: "v22.0",
        });

        var extras = extrasOverride && typeof extrasOverride === "object"
          ? extrasOverride
          : { sessionInfoVersion: "3" };
        if (coexistence) {
          extras = Object.assign({}, window.MetaSignupBridge._coexistenceExtras(), extras);
        } else if (!extras.setup) {
          extras.setup = {};
        }

        window.FB.login(
          function (response) {
            if (!response || !response.authResponse || !response.authResponse.code) {
              session.cancelled = true;
              window.MetaSignupBridge._finishSession(session, null);
              return;
            }

            session.code = response.authResponse.code;
            window.__metaSignupLastCode = session.code;
            if (response.authResponse.grantedScopes) {
              session.grantedScopes = response.authResponse.grantedScopes;
            }
            window.MetaSignupBridge._tryComplete(session);
          },
          {
            config_id: configId,
            response_type: "code",
            override_default_response_type: true,
            extras: extras,
          }
        );
      },
      function () {
        window.MetaSignupBridge._finishSession(session, null);
      }
    );
  },
};

function callbackNameSafe(name) {
  return name;
}
