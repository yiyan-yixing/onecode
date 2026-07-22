if (typeof SecurityError === 'undefined') {
  globalThis.SecurityError = class SecurityError extends Error {
    constructor(m) {
      super(m);
      this.name = 'SecurityError';
    }
  };
}
