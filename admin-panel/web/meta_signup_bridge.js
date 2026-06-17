window.MetaSignupBridge = {
  launch: function (appId, configId, coexistence, callbackName) {
    if (!window.FB) {
      window[callbackName](null);
      return;
    }

    window.FB.init({
      appId: appId,
      cookie: true,
      xfbml: false,
      version: "v22.0",
    });

    var extras = {
      sessionInfoVersion: "3",
    };
    if (coexistence) {
      extras.featureType = "whatsapp_business_app_onboarding";
    }

    window.FB.login(
      function (response) {
        if (!response || !response.authResponse || !response.authResponse.code) {
          window[callbackName](null);
          return;
        }

        var payload = {
          code: response.authResponse.code,
        };

        if (response.authResponse && response.authResponse.grantedScopes) {
          payload.granted_scopes = response.authResponse.grantedScopes;
        }

        window[callbackName](payload);
      },
      {
        config_id: configId,
        response_type: "code",
        override_default_response_type: true,
        extras: extras,
      }
    );

    window.addEventListener("message", function (event) {
      if (!event || !event.data || event.data.type !== "WA_EMBEDDED_SIGNUP") {
        return;
      }
      var data = event.data.data || {};
      window[callbackName]({
        code: window.__metaSignupLastCode || "",
        waba_id: data.waba_id,
        phone_number_id: data.phone_number_id,
        display_phone_number: data.display_phone_number,
      });
    });
  },
};
