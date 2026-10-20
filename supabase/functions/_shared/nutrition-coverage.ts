/** Keep partial estimates from being presented as whole-recipe totals. */
export function normalizeNutritionCoverage(recipe: Record<string, any>) {
  const nutrition = recipe.nutrition;
  if (!nutrition || typeof nutrition !== "object") return;
  const ingredients = (Array.isArray(recipe.parts) ? recipe.parts : [])
    .flatMap((part: any) => Array.isArray(part?.ingredients) ? part.ingredients : []);
  const quantified = (item: any) => typeof item?.amount === "number" &&
    Number.isFinite(item.amount) && item.amount >= 0 &&
    typeof item.unit === "string" && item.unit.trim().length > 0;
  const unknown = ingredients.filter((item: any) => !quantified(item))
    .map((item: any) => String(item?.name ?? "").trim()).filter(Boolean);
  const excluded = Array.isArray(nutrition.excluded_ingredients)
    ? nutrition.excluded_ingredients.filter((item: unknown): item is string => typeof item === "string" && item.trim().length > 0)
    : [];
  const keys = ["calories", "protein_grams", "fat_grams", "carbohydrate_grams"];
  const hasValues = keys.some((key) => typeof nutrition[key] === "number" &&
    Number.isFinite(nutrition[key]) && nutrition[key] >= 0);
  if (!ingredients.some(quantified)) {
    for (const key of keys) nutrition[key] = null;
    nutrition.basis = "unknown";
    nutrition.excluded_ingredients = [...new Set([...excluded, ...unknown])];
  } else if (hasValues && (unknown.length > 0 || excluded.length > 0)) {
    nutrition.basis = "known_ingredients_total";
    nutrition.excluded_ingredients = [...new Set([...excluded, ...unknown])];
  }
}
