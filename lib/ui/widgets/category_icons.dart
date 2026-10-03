import 'package:flutter/material.dart';

/// Ícones disponíveis para categorias (chaves persistidas → ícones).
const Map<String, IconData> categoryIcons = {
  'salary': Icons.payments_outlined,
  'work': Icons.work_outline,
  'investment': Icons.trending_up,
  'home': Icons.home_outlined,
  'apartment': Icons.apartment_outlined,
  'energy': Icons.bolt_outlined,
  'wifi': Icons.wifi,
  'food': Icons.restaurant_menu,
  'cart': Icons.shopping_cart_outlined,
  'restaurant': Icons.restaurant,
  'car': Icons.directions_car_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'taxi': Icons.local_taxi_outlined,
  'health': Icons.favorite_outline,
  'leisure': Icons.sports_esports_outlined,
  'school': Icons.school_outlined,
  'subscription': Icons.subscriptions_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'flight': Icons.flight_takeoff,
  'pet': Icons.pets_outlined,
  'gift': Icons.card_giftcard,
  'other': Icons.more_horiz,
};

IconData categoryIcon(String? key) => categoryIcons[key] ?? Icons.more_horiz;

const List<int> palette = [
  0xFF2457D6,
  0xFF0E7490,
  0xFF15803D,
  0xFF7C3AED,
  0xFFEA580C,
  0xFFDB2777,
  0xFFCA8A04,
  0xFF0D9488,
  0xFFDC2626,
  0xFF64748B,
];
