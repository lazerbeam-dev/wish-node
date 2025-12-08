import 'package:flutter/material.dart';
import 'item_card.dart';

class Vault extends StatelessWidget {
	final List<Map<String, dynamic>> items;
	final int crossAxisCount;

	const Vault({
		super.key,
		required this.items,
		this.crossAxisCount = 3,
	});

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: const Color(0xFF0F1115),
			appBar: AppBar(
				backgroundColor: Colors.black,
				leading: IconButton(
					icon: const Icon(Icons.arrow_back, color: Colors.white),
					onPressed: () => Navigator.pop(context),
				),
				title: const Text('Vault'),
			),
			body: SafeArea(
				child: Padding(
					padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
					child: GridView.builder(
						itemCount: items.length,
						gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
							crossAxisCount: crossAxisCount,
							crossAxisSpacing: 12,
							mainAxisSpacing: 12,
							childAspectRatio: 2.6,
						),
						itemBuilder: (context, index) {
							return ItemCard(item: items[index]);
						},
					),
				),
			),
		);
	}
}
