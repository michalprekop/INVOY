import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react';
import { createPortal } from 'react-dom';
import './tooltip.css';

const tooltipID = 'invoy-control-tooltip';

/** One tooltip layer for icon controls, including controls in dialogs and scroll panels. */
export function Tooltips() {
  const [active, setActive] = useState<{ anchor: HTMLElement; text: string } | null>(null);
  const [position, setPosition] = useState<CSSProperties>({ visibility: 'hidden' });
  const bubble = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const control = (target: EventTarget | null) =>
      target instanceof Element ? target.closest<HTMLElement>('button, a, summary') : null;
    const show = (anchor: HTMLElement | null) => {
      const text =
        anchor?.dataset.tooltip ||
        (!anchor?.textContent?.trim() ? anchor?.getAttribute('aria-label') : null);
      setActive((prior) =>
        anchor && text
          ? prior?.anchor === anchor && prior.text === text
            ? prior
            : { anchor, text }
          : null,
      );
    };
    const enter = (event: PointerEvent) => {
      if (event.pointerType !== 'touch') show(control(event.target));
    };
    const leave = (event: PointerEvent) => {
      if (control(event.target) !== control(event.relatedTarget)) setActive(null);
    };
    const focus = (event: FocusEvent) => show(control(event.target));
    const hide = () => setActive(null);
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') hide();
    };
    const removed = new MutationObserver(() => {
      setActive((prior) => (prior?.anchor.isConnected ? prior : null));
    });
    removed.observe(document.body, { childList: true, subtree: true });
    document.addEventListener('pointerover', enter);
    document.addEventListener('pointerout', leave);
    document.addEventListener('focusin', focus);
    document.addEventListener('focusout', hide);
    document.addEventListener('pointerdown', hide, true);
    document.addEventListener('click', hide, true);
    document.addEventListener('keydown', key, true);
    window.addEventListener('scroll', hide, true);
    window.addEventListener('resize', hide);
    window.addEventListener('blur', hide);
    return () => {
      removed.disconnect();
      document.removeEventListener('pointerover', enter);
      document.removeEventListener('pointerout', leave);
      document.removeEventListener('focusin', focus);
      document.removeEventListener('focusout', hide);
      document.removeEventListener('pointerdown', hide, true);
      document.removeEventListener('click', hide, true);
      document.removeEventListener('keydown', key, true);
      window.removeEventListener('scroll', hide, true);
      window.removeEventListener('resize', hide);
      window.removeEventListener('blur', hide);
    };
  }, []);

  useLayoutEffect(() => {
    if (!active || !bubble.current) return;
    const rect = active.anchor.getBoundingClientRect();
    const box = bubble.current.getBoundingClientRect();
    const left = Math.max(
      8,
      Math.min(rect.left + rect.width / 2 - box.width / 2, innerWidth - box.width - 8),
    );
    const above = rect.bottom + box.height + 14 > innerHeight && rect.top > box.height + 14;
    setPosition({
      left,
      top: above ? rect.top - box.height - 8 : rect.bottom + 8,
      '--tooltip-arrow': `${rect.left + rect.width / 2 - left}px`,
    } as CSSProperties);
    bubble.current.dataset.side = above ? 'above' : 'below';
    const descriptions = active.anchor.getAttribute('aria-describedby');
    active.anchor.setAttribute(
      'aria-describedby',
      [descriptions, tooltipID].filter(Boolean).join(' '),
    );
    return () => {
      if (descriptions) active.anchor.setAttribute('aria-describedby', descriptions);
      else active.anchor.removeAttribute('aria-describedby');
    };
  }, [active]);

  return active
    ? createPortal(
        <div
          ref={bubble}
          id={tooltipID}
          role="tooltip"
          className="control-tooltip"
          style={position}
        >
          {active.text}
        </div>,
        document.body,
      )
    : null;
}
