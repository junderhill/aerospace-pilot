const copyButton = document.querySelector("[data-copy-target]");

if (copyButton) {
  copyButton.addEventListener("click", async () => {
    const command = document.getElementById(copyButton.dataset.copyTarget);
    const status = document.querySelector(".copy-status");

    if (!command || !status) return;

    try {
      await navigator.clipboard.writeText(command.textContent.trim());
      copyButton.querySelector(".copy-label").textContent = "Copied";
      status.textContent = "Install command copied.";
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(command);
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = "Command selected. Press Command-C to copy.";
    }

    window.setTimeout(() => {
      copyButton.querySelector(".copy-label").textContent = "Copy";
      status.textContent = "";
    }, 2400);
  });
}
