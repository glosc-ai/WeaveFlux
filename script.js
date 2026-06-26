const menuButton = document.querySelector('[data-menu-button]');
const siteNav = document.querySelector('[data-site-nav]');
const siteHeader = document.querySelector('[data-site-header]');
const featureContent = document.querySelector('[data-feature-content]');
const featureTabs = [...document.querySelectorAll('[data-feature]')];
const revealTargets = [
  ...document.querySelectorAll('.section-heading, .screen-card, .feature-panel, .principles article, .timeline div, .setup-box, .faq-list details'),
];

const featureCopy = {
  create: {
    kicker: '创作工作台',
    title: '把提示词、参考图和生成参数放在同一屏。',
    body: '支持文生视频与图生视频工作流，保留模型名、画面比例、动态幅度等常用控制项。',
    screenshot: '创作工作台截图',
    file: 'workspace.png',
  },
  queue: {
    kicker: '任务轨道',
    title: '让异步生成任务保持可追踪。',
    body: '生成中、失败、完成状态集中展示，失败任务可查看原始错误信息并重新尝试。',
    screenshot: '任务轨道截图',
    file: 'task-orbit.png',
  },
  gallery: {
    kicker: '私密画廊',
    title: '生成结果先留在本地，再决定是否导出。',
    body: '作品在应用内预览和管理，需要分享或归档时再写入系统相册的 WeaveFlux 目录。',
    screenshot: '私密画廊截图',
    file: 'private-gallery.png',
  },
  settings: {
    kicker: '端点配置',
    title: '模型服务由你选择，凭据保存在本机。',
    body: '填写 Base URL、API Key 和默认模型，测试连接后即可开始视频生成。',
    screenshot: '端点配置截图',
    file: 'settings.png',
  },
};

if (revealTargets.length > 0) {
  revealTargets.forEach((target) => target.classList.add('reveal'));

  if ('IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-visible');
          revealObserver.unobserve(entry.target);
        });
      },
      { threshold: 0.14 },
    );

    revealTargets.forEach((target) => revealObserver.observe(target));
  } else {
    revealTargets.forEach((target) => target.classList.add('is-visible'));
  }
}

function closeMenu() {
  if (!siteNav || !menuButton) return;
  siteNav.classList.remove('is-open');
  menuButton.setAttribute('aria-expanded', 'false');
}

if (menuButton && siteNav) {
  menuButton.addEventListener('click', () => {
    const isOpen = siteNav.classList.toggle('is-open');
    menuButton.setAttribute('aria-expanded', String(isOpen));
  });

  siteNav.addEventListener('click', (event) => {
    if (event.target instanceof HTMLAnchorElement) closeMenu();
  });

  document.addEventListener('click', (event) => {
    if (!siteHeader?.contains(event.target)) closeMenu();
  });
}

featureTabs.forEach((tab) => {
  tab.addEventListener('click', () => {
    const key = tab.dataset.feature;
    const copy = featureCopy[key];
    if (!copy || !featureContent) return;

    featureTabs.forEach((item) => {
      const active = item === tab;
      item.classList.toggle('is-active', active);
      item.setAttribute('aria-selected', String(active));
    });

    featureContent.querySelector('.feature-kicker').textContent = copy.kicker;
    featureContent.querySelector('h3').textContent = copy.title;
    featureContent.querySelector('p:not(.feature-kicker)').textContent = copy.body;
    featureContent.dataset.activeFeature = key;

    const visual = featureContent.querySelector('[data-feature-visual]');
    if (visual) {
      visual.className = 'feature-visual screenshot-placeholder feature-shot';
      visual.innerHTML = `
        <span>Screenshot</span>
        <strong>${copy.screenshot}</strong>
        <em>${copy.file}</em>
      `.trim();
    }
  });
});
