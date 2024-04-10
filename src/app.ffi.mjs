export function catch_keydown_message(callback) {
  document.addEventListener("DOMContentLoaded", () => {
    document.addEventListener("keydown", (event) => {
      if (
        event.target.tagName == "TEXTAREA" ||
        event.target.tagName == "INPUT"
      ) {
        // We don't want to catch keydown events that take place in a textarea
        // or input.
        // So here we do nothing!
      } else {
        // Otherwise we catch it and run the callback with the event's key.
        callback(event.key);
      }
    });
  });
}
