!function () {
  if (!navigator.serviceWorker) {
    return;
  }
  var fk = {
    scope: '/',
    unregister: function () {
      return Promise.resolve();
    },
    active: {
      postMessage: function () {},
      state: 'activated',
      scriptURL: '',
    },
    waiting: null,
    installing: null,
    addEventListener: function () {},
    removeEventListener: function () {},
    update: function () {
      return Promise.resolve(fk);
    },
  };
  var o = navigator.serviceWorker.register.bind(navigator.serviceWorker);
  navigator.serviceWorker.register = function (u, opts) {
    return o(u, opts).catch(function () {
      fk.scope = (opts && opts.scope) || '/';
      return fk;
    });
  };
  try {
    Object.defineProperty(navigator.serviceWorker, 'ready', {
      get: function () {
        return Promise.resolve(fk);
      },
      configurable: true,
    });
  } catch (e) {
    // property may not be configurable
  }
  try {
    Object.defineProperty(navigator.serviceWorker, 'controller', {
      value: null,
      writable: true,
      configurable: true,
    });
  } catch (e) {
    // property may not be configurable
  }
}();
