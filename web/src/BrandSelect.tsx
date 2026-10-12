import {
  Children,
  isValidElement,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { Check, ChevronDown } from 'lucide-react';

type Option = { value: string; label: string; disabled: boolean };
function text(node: ReactNode): string {
  return Children.toArray(node)
    .map((child) =>
      isValidElement<{ children?: ReactNode }>(child) ? text(child.props.children) : String(child),
    )
    .join('');
}
function optionsFrom(children: ReactNode): Option[] {
  return Children.toArray(children).flatMap((child) => {
    if (!isValidElement<{ value?: string; children?: ReactNode; disabled?: boolean }>(child))
      return [];
    if (child.type !== 'option') return optionsFrom(child.props.children);
    const label = text(child.props.children);
    return [{ value: child.props.value ?? label, label, disabled: !!child.props.disabled }];
  });
}

type Props = Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'value' | 'onChange' | 'children'> & {
  value: string;
  onValueChange: (value: string) => void;
  leadingIcon?: ReactNode;
  children: ReactNode;
};

/** Shared popup: the trigger retains focus, including inside modal focus traps. */
export function BrandSelect({
  value,
  onValueChange,
  leadingIcon,
  children,
  className = '',
  title,
  ...props
}: Props) {
  const options = optionsFrom(children);
  const selected = options.findIndex((option) => option.value === value);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(selected);
  const [position, setPosition] = useState<CSSProperties>({ visibility: 'hidden' });
  const trigger = useRef<HTMLButtonElement>(null);
  const popup = useRef<HTMLDivElement>(null);
  const search = useRef({ text: '', time: 0 });
  const listID = useId();
  const choose = (index: number) => {
    const option = options[index];
    if (!option || option.disabled) return;
    setOpen(false);
    trigger.current?.focus();
    onValueChange(option.value);
  };
  const show = () => {
    setActive(selected >= 0 ? selected : options.findIndex((option) => !option.disabled));
    setOpen(true);
  };
  useLayoutEffect(() => {
    if (!open) return;
    const place = () => {
      const rect = trigger.current!.getBoundingClientRect();
      const width = Math.min(Math.max(rect.width, 200), window.innerWidth - 24);
      const below = window.innerHeight - rect.bottom - 18;
      const above = rect.top - 18;
      const upwards = below < Math.min(280, options.length * 40 + 12) && above > below;
      setPosition({
        left: Math.max(12, Math.min(rect.left, window.innerWidth - width - 12)),
        width,
        ...(upwards ? { bottom: window.innerHeight - rect.top + 6 } : { top: rect.bottom + 6 }),
        maxHeight: Math.max(40, Math.min(280, upwards ? above : below)),
      });
    };
    place();
    window.addEventListener('resize', place);
    window.addEventListener('scroll', place, true);
    const outside = (event: PointerEvent) => {
      if (
        !trigger.current?.contains(event.target as Node) &&
        !popup.current?.contains(event.target as Node)
      )
        setOpen(false);
    };
    document.addEventListener('pointerdown', outside);
    return () => {
      window.removeEventListener('resize', place);
      window.removeEventListener('scroll', place, true);
      document.removeEventListener('pointerdown', outside);
    };
  }, [open, options.length]);
  useEffect(() => {
    if (open)
      popup.current
        ?.querySelector<HTMLElement>(`[data-index="${active}"]`)
        ?.scrollIntoView({ block: 'nearest' });
  }, [open, active]);
  return (
    <>
      <button
        data-tooltip={props['aria-label'] ?? title}
        {...props}
        ref={trigger}
        type="button"
        role="combobox"
        className={`brand-select ${className}`}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-controls={open ? listID : undefined}
        aria-activedescendant={open && active >= 0 ? `${listID}-${active}` : undefined}
        onClick={() => (open ? setOpen(false) : show())}
        onBlur={(event) => {
          if (!popup.current?.contains(event.relatedTarget)) setOpen(false);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape' && open) {
            event.preventDefault();
            event.stopPropagation();
            setOpen(false);
            return;
          }
          if (event.key === 'Tab') {
            setOpen(false);
            return;
          }
          if (['Enter', ' '].includes(event.key)) {
            event.preventDefault();
            if (open) choose(active);
            else show();
            return;
          }
          const enabled = options
            .map((option, index) => (option.disabled ? -1 : index))
            .filter((index) => index >= 0);
          if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
            event.preventDefault();
            if (!open) {
              show();
              return;
            }
            const current = enabled.indexOf(active);
            setActive(
              event.key === 'Home'
                ? enabled[0]
                : event.key === 'End'
                  ? enabled.at(-1)!
                  : enabled[
                      (current + (event.key === 'ArrowDown' ? 1 : -1) + enabled.length) %
                        enabled.length
                    ],
            );
          } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
            event.preventDefault();
            const now = Date.now();
            const next =
              now - search.current.time > 700 ? event.key : search.current.text + event.key;
            search.current = { text: next, time: now };
            const match = options.findIndex(
              (option) =>
                !option.disabled &&
                option.label.toLocaleLowerCase('sk').startsWith(next.toLocaleLowerCase('sk')),
            );
            if (match >= 0) {
              setOpen(true);
              setActive(match);
            }
          }
        }}
      >
        {leadingIcon}
        <span>{options[selected]?.label === '⌄' ? '' : options[selected]?.label || '\u00a0'}</span>
        <ChevronDown size={12} aria-hidden="true" />
      </button>
      {open &&
        createPortal(
          <div
            ref={popup}
            id={listID}
            className="brand-select-list"
            style={position}
            role="listbox"
            aria-label={props['aria-label'] ?? title}
            onMouseDown={(event) => event.preventDefault()}
          >
            {options.map((option, index) => (
              <button
                type="button"
                role="option"
                tabIndex={-1}
                id={`${listID}-${index}`}
                key={option.value}
                data-index={index}
                aria-selected={option.value === value}
                aria-disabled={option.disabled || undefined}
                className={index === active ? 'highlighted' : ''}
                onPointerMove={() => {
                  if (!option.disabled) setActive(index);
                }}
                onClick={() => choose(index)}
              >
                <span>{option.label || 'Bez výberu'}</span>
                {option.value === value && <Check size={14} aria-hidden="true" />}
              </button>
            ))}
            {!options.length && <span className="dropdown-empty">Žiadne možnosti</span>}
          </div>,
          trigger.current?.closest('[role="dialog"]') ?? document.body,
        )}
    </>
  );
}
