import { useEffect } from "react";

interface Props {
  message: string;
  onDismiss: () => void;
}

export function Toast({ message, onDismiss }: Props) {
  useEffect(() => {
    const t = setTimeout(onDismiss, 2000);
    return () => clearTimeout(t);
  }, [onDismiss]);

  return (
    <div
      className="fixed bottom-16 left-1/2 -translate-x-1/2 z-50
                 bg-neutral-800 text-white text-xs font-medium px-4 py-2
                 rounded-md shadow-lg pointer-events-none select-none
                 animate-in fade-in slide-in-from-bottom-2 duration-150"
    >
      {message}
    </div>
  );
}
