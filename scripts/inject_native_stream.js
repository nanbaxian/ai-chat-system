(() => {
  window.injectFlutterNativeStream = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      window.flutterNativeStream = stream;
      console.log("Injected native stream for Flutter:", stream);
      return stream;
    } catch (error) {
      console.error("Failed to inject native stream:", error);
      throw error;
    }
  };
  console.log("Call injectFlutterNativeStream() in the browser console to push a native stream into Flutter.");
})();
