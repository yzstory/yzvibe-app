const dialog = document.querySelector('#image-dialog');
const dialogImage = document.querySelector('#dialog-image');
const dialogTitle = document.querySelector('#dialog-title');
let lastImageTrigger;

document.querySelectorAll('[data-image]').forEach((button) => {
  button.addEventListener('click', () => {
    lastImageTrigger = button;
    dialogImage.src = button.dataset.image;
    dialogImage.alt = button.querySelector('img').alt;
    dialogTitle.textContent = button.dataset.title;
    dialog.showModal();
  });
});
document.querySelector('#close-dialog').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', (event) => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
});
dialog.addEventListener('close', () => lastImageTrigger?.focus({ preventScroll: true }));

const copyButton = document.querySelector('#copy-command');
const copyStatus = document.querySelector('#copy-status');
copyButton.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(document.querySelector('#install-command').textContent.trim());
    copyStatus.textContent = '已复制，可以粘贴到电脑终端。';
    copyButton.textContent = '再次复制';
  } catch {
    copyStatus.textContent = '未能自动复制，请选中上方命令手动复制。';
  }
});

if ('IntersectionObserver' in window) {
  const links = Array.from(document.querySelectorAll('.contents a'));
  const observer = new IntersectionObserver((entries) => {
    const visible = entries.filter((entry) => entry.isIntersecting);
    if (!visible.length) return;
    const id = visible[0].target.id;
    links.forEach((link) => {
      if (link.hash === `#${id}`) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    });
  }, { rootMargin: '-8% 0px -55% 0px', threshold: 0 });
  document.querySelectorAll('.story-section').forEach((section) => observer.observe(section));
}
