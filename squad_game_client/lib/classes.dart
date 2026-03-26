class Armor {
  final String name;
  final int cost;
  final int defense;
  final String description;
  final int durability;
  final String type;

  Armor({
    required this.name,
    required this.cost,
    required this.defense,
    required this.description,
    required this.type,
    this.durability = 100,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'cost': cost,
      'defense': defense,
      'description': description,
      'durability': durability,
      'type': type,
    };
  }
}

class Properties {
  final String name;
  final String description;
  final int cost;
  final int income;

  Properties({
    required this.name,
    required this.description,
    required this.cost,
    required this.income,
  });
}

class Vehicle {
  final String name;
  final int power;
  final int cost;
  final int skillReq;
  final String description;
  final int defense;

  

  Vehicle({
    required this.name,
    required this.power,
    required this.cost,
    required this.skillReq,
    required this.description,
    required this.defense,
  });

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      name: map['name'],
      power: map['power'],
      cost: map['cost'],
      skillReq: map['skillReq'],
      description: map['description'],
      defense: map['defense'],
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'power': power,
      'cost': cost,
      'skillReq': skillReq,
      'description': description,
      'defense': defense,
    };
  }
}

class Weapon {
  final String name;
  final String description;
  final int power;
  final int cost;

  Weapon({
    required this.name,
    required this.description,
    required this.power,
    required this.cost,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'power': power,
      'cost': cost,
      'type': 'weapon',
    };
  }
}