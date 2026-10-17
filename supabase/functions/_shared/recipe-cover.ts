// Choose existing extracted frames, never reorder evidence images.
export function chooseVideoRecipeCovers(
  recipes: unknown[], firstFrameIndex: number, frameCount: number,
): number | null {
  if (frameCount <= 0) return null;
  const valid = (value: unknown): value is number => typeof value === 'number' &&
    Number.isInteger(value) && value >= firstFrameIndex && value < firstFrameIndex + frameCount;
  let thumbnail: number | null = null;
  for (const value of recipes) {
    if (value == null || typeof value !== 'object') continue;
    const recipe = value as Record<string, unknown>;
    let selected = valid(recipe.cover_image_index) ? recipe.cover_image_index : null;
    if (selected == null) {
      const parts = Array.isArray(recipe.parts) ? recipe.parts : [];
      const steps = parts.flatMap((part) => Array.isArray(part?.steps) ? part.steps : []);
      for (const step of steps.reverse()) {
        if (valid(step?.image_index)) { selected = step.image_index; break; }
      }
    }
    recipe.cover_image_index = selected ?? firstFrameIndex;
    thumbnail ??= recipe.cover_image_index as number;
  }
  return thumbnail ?? firstFrameIndex;
}

export function validThumbnailIndex(media: Record<string, unknown>, count: number): number {
  const index = media.thumbnail_index;
  return typeof index === 'number' && Number.isInteger(index) && index >= 0 && index < count ? index : 0;
}
