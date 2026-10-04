import invoice from './assets/product/invoice.webp';
import invoice2x from './assets/product/invoice@2x.webp';
import invoice3x from './assets/product/invoice@3x.webp';
import overview from './assets/product/overview.webp';
import overview2x from './assets/product/overview@2x.webp';
import overview3x from './assets/product/overview@3x.webp';

const previews = {
  invoice: {
    src: invoice,
    srcSet: `${invoice} 1328w, ${invoice2x} 2656w, ${invoice3x} 3984w`,
    alt: 'INVOY: náhľad faktúry v šablóne Manolo & Bay, s vymyslenými údajmi.',
  },
  overview: {
    src: overview,
    srcSet: `${overview} 1328w, ${overview2x} 2656w, ${overview3x} 3984w`,
    alt: 'INVOY: tabuľkový prehľad faktúr, odberateľov, súm a stavov úhrady.',
  },
};

export function ProductPreview({
  preview,
  className,
  eager = false,
}: {
  preview: keyof typeof previews;
  className?: string;
  eager?: boolean;
}) {
  return (
    <img
      {...previews[preview]}
      className={className}
      sizes="(min-width: 1440px) 1328px, 100vw"
      width="1328"
      height="747"
      loading={eager ? 'eager' : 'lazy'}
      fetchPriority={eager ? 'high' : 'auto'}
    />
  );
}
