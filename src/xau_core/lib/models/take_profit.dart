/// Take-profit value type.
library;

/// A single take-profit target. [index] is 1-based (1, 2, 3).
class TakeProfit {
  final int index;
  final double price;

  TakeProfit({required this.index, required this.price}) {
    if (index < 1) {
      throw ArgumentError('TakeProfit index must be >= 1, got $index.');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'price': price,
      };

  factory TakeProfit.fromJson(Map<String, Object?> json) {
    return TakeProfit(
      index: (json['index'] as num).toInt(),
      price: (json['price'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TakeProfit && other.index == index && other.price == price;

  @override
  int get hashCode => Object.hash(index, price);

  @override
  String toString() => 'TakeProfit(TP$index: $price)';
}
