import type { Page } from '@playwright/test';

export async function showWalkthroughStep(
  page: Page,
  step: number,
  message: string,
  holdMilliseconds = 2_000,
): Promise<void> {
  if (!Number.isInteger(step) || step <= 0) {
    throw new Error('Walkthrough step must be a positive integer.');
  }
  if (!message.trim()) {
    throw new Error('Walkthrough message must not be blank.');
  }
  if (!Number.isFinite(holdMilliseconds) || holdMilliseconds < 0) {
    throw new Error('Walkthrough hold must be a non-negative finite number.');
  }

  await page.evaluate(
    ({ step, message }) => {
      const overlay = document.createElement('section');
      const eyebrow = document.createElement('div');
      const copy = document.createElement('div');

      eyebrow.textContent = `STEP ${step}`;
      copy.textContent = message;
      overlay.dataset.walkthroughOverlay = 'true';
      Object.assign(overlay.style, {
        position: 'fixed',
        zIndex: '2147483647',
        left: '40px',
        right: '40px',
        bottom: '48px',
        display: 'grid',
        gap: '6px',
        justifyItems: 'center',
        padding: '14px 18px',
        border: '1px solid rgba(255, 255, 255, 0.28)',
        borderRadius: '10px',
        background: 'rgba(24, 27, 29, 0.94)',
        boxShadow: '0 12px 32px rgba(0, 0, 0, 0.28)',
        color: '#fff',
        fontFamily: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        fontWeight: '600',
        textAlign: 'center',
        pointerEvents: 'none',
        opacity: '0',
        transform: 'translateY(8px)',
        transition: 'opacity 180ms ease, transform 180ms ease',
      });
      Object.assign(eyebrow.style, {
        fontSize: '12px',
        letterSpacing: '0.12em',
        textTransform: 'uppercase',
        opacity: '0.72',
      });
      Object.assign(copy.style, { fontSize: 'clamp(16px, 2vw, 22px)' });

      overlay.append(eyebrow, copy);
      document.body.append(overlay);
      requestAnimationFrame(() => {
        overlay.style.opacity = '1';
        overlay.style.transform = 'translateY(0)';
      });
    },
    { step, message: message.trim() },
  );

  await page.waitForTimeout(180);
  try {
    await page.waitForTimeout(holdMilliseconds);
  } finally {
    await page.evaluate(async () => {
      const overlay = document.querySelector('[data-walkthrough-overlay="true"]');
      if (!overlay) return;

      (overlay as HTMLElement).style.opacity = '0';
      (overlay as HTMLElement).style.transform = 'translateY(8px)';
      await new Promise((resolve) => window.setTimeout(resolve, 180));
      overlay.remove();
    });
  }
}
