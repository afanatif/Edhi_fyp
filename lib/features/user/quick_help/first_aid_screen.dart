import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_shell.dart';

class FirstAidScreen extends StatelessWidget {
  const FirstAidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guides = [
      {
        'title': 'Cardiopulmonary Resuscitation (CPR)',
        'category': 'Critical Life Support',
        'icon': Icons.monitor_heart,
        'color': AppColors.emergencyRed,
        'steps': [
          '1. Check responsiveness: Tap victim and shout "Are you okay?".',
          '2. Call 115 immediately or tell someone specifically to call.',
          '3. Check breathing: Look, listen, and feel for chest movement (no more than 10 seconds).',
          '4. Hand placement: Place the heel of one hand in the center of the chest, interlock fingers with other hand.',
          '5. Chest compressions: Push hard and fast at 100-120 beats per minute, at least 2 inches deep. Give 30 compressions.',
          '6. Rescue breaths: Tilt head back, lift chin, pinch nose, and deliver 2 gentle breaths until chest rises.',
          '7. Repeat cycle of 30 compressions and 2 breaths until paramedics arrive.',
        ],
        'warning': 'Do NOT interrupt compressions for more than 10 seconds.',
      },
      {
        'title': 'Severe Bleeding & Hemorrhage',
        'category': 'Trauma & Wound Care',
        'icon': Icons.bloodtype,
        'color': const Color(0xFFC026D3),
        'steps': [
          '1. Ensure scene safety and put on gloves if available.',
          '2. Apply direct, firm, continuous pressure directly over the wound using a clean cloth or sterile gauze.',
          '3. Do NOT remove soaked dressings; add more layers on top.',
          '4. If on an arm or leg, elevate the injured limb above heart level while maintaining pressure.',
          '5. Keep patient calm and lying down to prevent shock.',
          '6. If life-threatening arterial spurting continues, apply a tourniquet 2-3 inches above the wound (tighten until bleeding stops).',
        ],
        'warning':
            'Never remove deeply impaled objects; stabilize them in place with rolled dressings.',
      },
      {
        'title': 'Burns & Scalds',
        'category': 'Thermal Emergencies',
        'icon': Icons.local_fire_department,
        'color': Colors.deepOrange,
        'steps': [
          '1. Stop the burning: Remove person from the heat source.',
          '2. Cool the burn: Hold under cool running tap water for at least 10 to 20 minutes.',
          '3. Remove tight items: Gently remove rings, belts, or tight clothing before swelling begins.',
          '4. Cover loosely: Use a sterile non-stick bandage or clean plastic cling wrap.',
          '5. Protect from chills: Keep the non-burned areas warm.',
        ],
        'warning':
            'NEVER apply ice, toothpaste, butter, or oil to a burn. Do NOT pop blisters.',
      },
      {
        'title': 'Bone Fractures & Dislocations',
        'category': 'Orthopedic Trauma',
        'icon': Icons.personal_injury,
        'color': Colors.blueGrey,
        'steps': [
          '1. Immobilize the injured area: Do not attempt to realign or push protruding bones back in.',
          '2. Control bleeding if present by applying pressure around (not on) protruding bone.',
          '3. Apply splint: Use rolled magazines, cardboard, or wooden slats padded with cloth to stabilize joints above and below fracture.',
          '4. Apply ice packs wrapped in a towel for 15-20 minutes to reduce swelling.',
          '5. Treat for shock: Keep patient lying flat and covered with a blanket.',
        ],
        'warning':
            'If neck or spinal injury is suspected, DO NOT move the person unless in imminent danger of fire or explosion.',
      },
      {
        'title': 'Choking (Heimlich Maneuver)',
        'category': 'Airway Obstruction',
        'icon': Icons.warning,
        'color': Colors.amber.shade900,
        'steps': [
          '1. Ask: "Are you choking?". If they can cough forcefully or speak, encourage coughing.',
          '2. If unable to breathe or speak: Stand behind person, lean them slightly forward.',
          '3. Back blows: Deliver 5 sharp blows between their shoulder blades with the heel of your hand.',
          '4. Abdominal thrusts: Make a fist just above the navel, grasp with other hand, and give 5 quick upward thrusts.',
          '5. Alternate 5 back blows and 5 thrusts until airway is cleared.',
          '6. If victim becomes unconscious, lower to floor and start CPR.',
        ],
        'warning':
            'For choking infants under 1 year, use gentle chest thrusts instead of abdominal thrusts.',
      },
    ];

    return ResponsiveShell(
      appBar: AppBar(
        title: const Text('First Aid Guides & Protocols'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: guides.length,
        itemBuilder: (context, index) {
          final g = guides[index];
          final color = g['color'] as Color;
          final steps = g['steps'] as List<String>;
          final warning = g['warning'] as String;

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border),
            ),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.all(16),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(g['icon'] as IconData, color: color, size: 24),
                ),
                title: Text(
                  g['title'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  g['category'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        ...steps.map(
                          (step) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              step,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber,
                                size: 18,
                                color: Colors.amber.shade900,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  warning,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
