export function Rating({ rating = 0 }: { rating?: number }) {
  const numSections = 10;

  const getColor = (ratingValue: number) => {
    if (ratingValue <= 30) return 'bg-red-500';
    if (ratingValue <= 60) return 'bg-yellow-400';
    return 'bg-green-500';
  };

  return (
    <div className="flex justify-start gap-[1px]">
      {Array.from(Array(numSections).keys()).map((num) => {
        const isFilled = num * 10 < rating;
        return (
          <div className="w-[8px] h-[8px]" key={num}>
            <div
              className={`w-full h-full rounded-[2px] ${
                isFilled ? getColor(rating) : 'bg-gray-200'
              }`}
            />
          </div>
        );
      })}
    </div>
  );
}
