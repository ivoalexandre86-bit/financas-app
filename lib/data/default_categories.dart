import '../domain/models/entities.dart';

/// Categorias padrão criadas para todo novo usuário (IDs estáveis por
/// usuário, para facilitar dados de exemplo e importações).
List<FinCategory> defaultCategories() {
  FinCategory c(
    String id,
    String name,
    CategoryKind kind,
    String icon,
    int color, [
    String? parent,
  ]) => FinCategory(
    id: id,
    name: name,
    kind: kind,
    icon: icon,
    color: color,
    parentId: parent,
  );
  const inc = CategoryKind.income;
  const exp = CategoryKind.expense;
  return [
    c('cat_salary', 'Salário', inc, 'salary', 0xFF15803D),
    c('cat_freelance', 'Freelance', inc, 'work', 0xFF0E7490),
    c('cat_investments', 'Investimentos', inc, 'investment', 0xFF7C3AED),
    c('cat_other_income', 'Outras receitas', inc, 'other', 0xFF64748B),
    c('cat_housing', 'Moradia', exp, 'home', 0xFF2457D6),
    c('cat_rent', 'Aluguel', exp, 'home', 0xFF2457D6, 'cat_housing'),
    c('cat_condo', 'Condomínio', exp, 'apartment', 0xFF2457D6, 'cat_housing'),
    c('cat_energy', 'Energia', exp, 'energy', 0xFF2457D6, 'cat_housing'),
    c('cat_internet', 'Internet', exp, 'wifi', 0xFF2457D6, 'cat_housing'),
    c('cat_food', 'Alimentação', exp, 'food', 0xFFEA580C),
    c('cat_groceries', 'Mercado', exp, 'cart', 0xFFEA580C, 'cat_food'),
    c(
      'cat_restaurants',
      'Restaurantes',
      exp,
      'restaurant',
      0xFFEA580C,
      'cat_food',
    ),
    c('cat_transport', 'Transporte', exp, 'car', 0xFF0891B2),
    c('cat_fuel', 'Combustível', exp, 'fuel', 0xFF0891B2, 'cat_transport'),
    c('cat_rides', 'Aplicativos', exp, 'taxi', 0xFF0891B2, 'cat_transport'),
    c('cat_health', 'Saúde', exp, 'health', 0xFFDC2626),
    c('cat_leisure', 'Lazer', exp, 'leisure', 0xFFDB2777),
    c('cat_education', 'Educação', exp, 'school', 0xFF9333EA),
    c('cat_subscriptions', 'Assinaturas', exp, 'subscription', 0xFF4F46E5),
    c('cat_shopping', 'Compras', exp, 'shopping', 0xFFCA8A04),
    c('cat_travel', 'Viagens', exp, 'flight', 0xFF0D9488),
    c('cat_other_expense', 'Outras despesas', exp, 'other', 0xFF64748B),
  ];
}
