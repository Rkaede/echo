import { VariantProps, cva } from 'cva';
import { HTMLAttributes, forwardRef } from 'react';

// Card
const card = cva(['rounded-lg border bg-card text-card-foreground shadow-sm']);

export const Card = forwardRef<
  HTMLDivElement,
  VariantProps<typeof card> & HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div data-component="Card" ref={ref} className={card({ className })} {...props} />
));

Card.displayName = 'Card';

// CardContent
const cardContent = cva(['p-6 pt-0']);

export const CardContent = forwardRef<
  HTMLDivElement,
  VariantProps<typeof card> & HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    data-component="CardContent"
    ref={ref}
    className={cardContent({ className })}
    {...props}
  />
));

CardContent.displayName = 'CardContent';

// CardTitle
const cardTitle = cva(['text-2xl font-semibold leading-none tracking-tight']);

export const CardTitle = forwardRef<
  HTMLParagraphElement,
  VariantProps<typeof card> & HTMLAttributes<HTMLHeadingElement>
>(({ className, ...props }, ref) => (
  <h3 data-component="CardTitle" ref={ref} className={cardTitle({ className })} {...props} />
));

CardTitle.displayName = 'CardTitle';

// CardHeader
const cardHeader = cva(['flex flex-col space-y-1.5 p-6']);

export const CardHeader = forwardRef<
  HTMLDivElement,
  VariantProps<typeof card> & HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div data-component="CardHeader" ref={ref} className={cardHeader({ className })} {...props} />
));

CardHeader.displayName = 'CardHeader';

// CardDescription
const cardDescription = cva(['text-sm text-muted-foreground']);
export const CardDescription = forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
  <p ref={ref} className={cardDescription({ className })} {...props} />
));

CardDescription.displayName = 'CardDescription';
