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

  _firstId: function (value) {
    if (Array.isArray(value)) {
      for (var i = 0; i < value.length; i++) {
        var item = value[i];
        if (item == null) continue;
        var text = String(item).trim();
        if (text) return text;
      }
      return "";
    }
    if (value == null) return "";
    return String(value).trim();
  },

  _tryComplete: function (session) {
    if (!session || session.finished) {
      return;
    }
    var code = session.code || window.__metaSignupLastCode || "";
    // v5: messaging_account_ids replaces waba_id. Never treat primary_waac_ids as messaging account.
    var messagingId =
      session.messagingAccountId ||
      window.MetaSignupBridge._firstId(session.messagingAccountIds) ||
      session.wabaId ||
      "";
    var phoneNumberId = session.phoneNumberId || "";
    if (!code || !messagingId || !phoneNumberId) {
      return;
    }
    window.MetaSignupBridge._finishSession(session, {
      code: code,
      waba_id: messagingId,
      messaging_account_id: messagingId,
      messaging_account_ids: session.messagingAccountIds || (messagingId ? [messagingId] : []),
      phone_number_id: phoneNumberId,
      display_phone_number: session.displayPhoneNumber || "",
      business_id: session.businessId || "",
      is_on_biz_app: !!session.isOnBizApp,
      event: session.event || "",
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

  _v5Extras: function () {
    // Coexistence (WhatsApp Business app onboarding) is on by default in v5 — do not opt out.
    return {
      setup: {},
      version: "v5",
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
      messagingAccountId: "",
      messagingAccountIds: [],
      phoneNumberId: "",
      displayPhoneNumber: "",
      businessId: "",
      isOnBizApp: false,
      event: "",
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
      var evt = payload.event || "";
      session.event = evt;
      if (evt === "CANCEL" || evt === "error" || evt === "ERROR") {
        session.cancelled = true;
        window.MetaSignupBridge._finishSession(session, null);
        return;
      }
      var data = payload.data || {};
      var messagingIds = data.messaging_account_ids || data.messagingAccountIds || [];
      var messagingId =
        window.MetaSignupBridge._firstId(messagingIds) ||
        window.MetaSignupBridge._firstId(data.messaging_account_id) ||
        window.MetaSignupBridge._firstId(data.waba_id);
      if (messagingId) {
        session.messagingAccountId = messagingId;
        session.wabaId = messagingId;
        session.messagingAccountIds = Array.isArray(messagingIds) && messagingIds.length
          ? messagingIds.map(function (id) { return String(id); })
          : [messagingId];
      }
      // Intentionally ignore primary_waac_ids — WAAC IDs must not be stored as messaging account IDs.
      if (data.phone_number_id) {
        session.phoneNumberId = String(data.phone_number_id);
      }
      var displayPhone = data.display_phone_number || data.displayPhoneNumber || data.phone_number || "";
      if (displayPhone) {
        session.displayPhoneNumber = String(displayPhone);
      }
      if (data.business_id) {
        session.businessId = String(data.business_id);
      }
      if (typeof data.is_on_biz_app === "boolean") {
        session.isOnBizApp = data.is_on_biz_app;
      } else if (
        evt === "FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING"
      ) {
        session.isOnBizApp = true;
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

        var extras = window.MetaSignupBridge._v5Extras();
        if (extrasOverride && typeof extrasOverride === "object") {
          extras = Object.assign({}, extras, extrasOverride);
          if (extrasOverride.setup && typeof extrasOverride.setup === "object") {
            extras.setup = Object.assign({}, extras.setup || {}, extrasOverride.setup);
          }
        }
        // Drop obsolete v3 keys if an old override still sends them.
        delete extras.sessionInfoVersion;
        delete extras.featureType;
        extras.version = "v5";
        if (coexistence === false) {
          extras.features = [{ name: "whatsapp_business_app_onboarding", enabled: false }];
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
