// Shared mobile navigation and attachment choices. Existing upload handlers remain authoritative.
export function enhanceAttachments(root = document) {
  for (const input of root.querySelectorAll('input[type="file"]:not([data-attachment-source])')) {
    input.dataset.attachmentSource = 'original';
    if(!input.hasAttribute('aria-label')) input.setAttribute('aria-label','ملف المرفق');
    const accept = input.accept.toLowerCase();
    const canPhoto = !accept || /image\/|\.(png|jpe?g|webp)(,|$)/.test(accept);
    if (!canPhoto) continue; // Structured imports and document-only controls keep their native picker.
    const controls = document.createElement('div');
    controls.className = 'atwar-attachment-controls';
    const files = document.createElement('div');
    files.className = 'atwar-attachment-preview';
    files.setAttribute('aria-live', 'polite');
    const camera = document.createElement('input');
    camera.type = 'file'; camera.accept = 'image/jpeg,image/png';
    camera.setAttribute('capture', 'environment'); camera.hidden = true;
    camera.dataset.attachmentSource = 'camera';
    const makeButton = (text, action) => {
      const b = document.createElement('button'); b.type = 'button'; b.textContent = text;
      b.addEventListener('click', e => { e.preventDefault(); action(); }); controls.append(b); return b;
    };
    const photoButton = makeButton('التصوير بالكاميرا', () => camera.click());
    const uploadButton = makeButton('رفع من الجهاز', () => input.click());
    const clear = makeButton('حذف المرفق', () => {
      input.value = ''; camera.value = ''; input.dispatchEvent(new Event('change', { bubbles: true }));
    });
    let urls = [];
    const refresh = () => {
      urls.forEach(URL.revokeObjectURL); urls = []; files.replaceChildren();
      const chosen = Array.from(input.files || []);
      clear.hidden = !chosen.length || input.dataset.attachmentPreview === 'native';
      photoButton.disabled = uploadButton.disabled = clear.disabled = input.disabled;
      for (const file of input.dataset.attachmentPreview === 'native' ? [] : chosen) {
        const item = document.createElement('div');
        if (/^image\/(jpeg|png|webp)$/.test(file.type)) {
          const image = document.createElement('img'); const url = URL.createObjectURL(file); urls.push(url);
          image.src = url; image.alt = 'معاينة المرفق'; item.append(image);
        }
        const name = document.createElement('span'); name.textContent = file.name; item.append(name); files.append(item);
      }
    };
    camera.addEventListener('change', () => {
      if (!camera.files.length) return;
      const transfer = new DataTransfer();
      for (const file of camera.files) transfer.items.add(file);
      input.files = transfer.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
      camera.value = '';
    });
    input.addEventListener('change', refresh);
    input.form?.addEventListener('reset', () => queueMicrotask(refresh));
    input.classList.add('atwar-file-native');
    if(getComputedStyle(input.parentElement).display.includes('flex')) input.parentElement.classList.add('atwar-attachment-host');
    input.after(controls, files, camera); refresh();
    // Release previews as soon as a dynamic form closes.
    const cleanup = new MutationObserver(() => {
      if (!input.isConnected) { urls.forEach(URL.revokeObjectURL); cleanup.disconnect(); }
    });
    cleanup.observe(document.body, { childList: true, subtree: true });
  }
}
export function startMobileExperience() {
  const setupNavigation = () => {
    const sidebar = document.querySelector('.atwar-sidebar');
    const header = document.querySelector('.atwar-topbar');
    if (!sidebar || !header || header.querySelector('.atwar-mobile-menu')) return;
    sidebar.id ||= 'atwarMobileNavigation';
    const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'atwar-mobile-menu';
    toggle.textContent = '☰'; toggle.setAttribute('aria-label', 'فتح القائمة'); toggle.setAttribute('aria-controls', sidebar.id); toggle.setAttribute('aria-expanded', 'false');
    const close = document.createElement('button'); close.type = 'button'; close.className = 'atwar-mobile-close'; close.textContent = 'إغلاق القائمة';
    const backdrop = document.createElement('button'); backdrop.type = 'button'; backdrop.className = 'atwar-mobile-backdrop'; backdrop.setAttribute('aria-label', 'إغلاق القائمة'); backdrop.tabIndex = -1;
    const media = matchMedia('(max-width: 700px)');
    const setOpen = (open, returnFocus = true) => {
      document.body.classList.toggle('atwar-navigation-open', open && media.matches);
      toggle.setAttribute('aria-expanded', String(open && media.matches));
      sidebar.inert = media.matches && !open;
      if (open && media.matches) close.focus(); else if (returnFocus) toggle.focus();
    };
    toggle.onclick = () => setOpen(toggle.getAttribute('aria-expanded') !== 'true');
    close.onclick = backdrop.onclick = () => setOpen(false);
    sidebar.addEventListener('click', e => { if (e.target.closest('a')) setOpen(false, false); });
    document.addEventListener('keydown', e => {
      if (toggle.getAttribute('aria-expanded') !== 'true') return;
      if (e.key === 'Escape') { e.preventDefault(); setOpen(false); }
      if (e.key === 'Tab') {
        const items = [...sidebar.querySelectorAll('button,a[href],input,select')].filter(el => !el.disabled && el.getClientRects().length);
        const first = items[0], last = items.at(-1);
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus(); }
      }
    });
    media.addEventListener('change', () => setOpen(false, false));
    sidebar.prepend(close); header.prepend(toggle); document.body.append(backdrop); setOpen(false, false);
  };
  let queued = false;
  const scan = () => { queued = false; setupNavigation(); enhanceAttachments(); };
  const observer = new MutationObserver(records => {
    if (!queued && records.some(r => r.addedNodes.length)) { queued = true; queueMicrotask(scan); }
  });
  observer.observe(document.body, { childList: true, subtree: true }); scan();
}
