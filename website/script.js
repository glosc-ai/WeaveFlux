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
    visualClass: 'feature-create',
    visual: `
      <div class="diagram-phone">
        <div class="diagram-topline"></div>
        <div class="diagram-canvas"><span></span></div>
        <div class="diagram-prompt"></div>
        <div class="diagram-controls"><i></i><i></i><i></i></div>
      </div>
      <div class="diagram-side">
        <span>Prompt</span>
        <strong>Video params</strong>
        <em>Generate</em>
      </div>
    `,
  },
  queue: {
    kicker: '任务轨道',
    title: '让异步生成任务保持可追踪。',
    body: '生成中、失败、完成状态集中展示，失败任务可查看原始错误信息并重新尝试。',
    visualClass: 'feature-queue',
    visual: `
      <div class="queue-board">
        <div class="diagram-task active"><span></span></div>
        <div class="diagram-task"></div>
        <div class="diagram-task failed"></div>
      </div>
    `,
  },
  gallery: {
    kicker: '私密画廊',
    title: '生成结果先留在本地，再决定是否导出。',
    body: '作品在应用内预览和管理，需要分享或归档时再写入系统相册的 WeaveFlux 目录。',
    visualClass: 'feature-gallery',
    visual: `
      <div class="gallery-board">
        <div class="gallery-tile"><span>00:05</span></div>
        <div class="gallery-tile"><span>00:08</span></div>
        <div class="gallery-tile"><span>HD</span></div>
        <div class="gallery-tile"><span>00:04</span></div>
      </div>
    `,
  },
  settings: {
    kicker: '端点配置',
    title: '模型服务由你选择，凭据保存在本机。',
    body: '填写 Base URL、API Key 和默认模型，测试连接后即可开始视频生成。',
    visualClass: 'feature-settings',
    visual: `
      <div class="settings-board">
        <div class="diagram-field"><span>Base URL</span><b>https://one.gloscai.com/v1</b></div>
        <div class="diagram-field"><span>API Key</span><b>••••••••••••••</b></div>
        <div class="diagram-field"><span>Model</span><b>video-generation</b></div>
        <div class="diagram-chip">Android KeyStore</div>
      </div>
    `,
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
      visual.className = `feature-visual feature-diagram ${copy.visualClass}`;
      visual.innerHTML = copy.visual.trim();
    }
  });
});
