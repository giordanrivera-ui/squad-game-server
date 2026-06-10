import 'package:flutter/material.dart';
import '../status_app_bar.dart';
import '../socket_service.dart';
import 'dart:async';
import 'injury_healing_tab_content.dart';

class HospitalManagerScreen extends StatefulWidget {
  final Map<String, dynamic> hospital;

  const HospitalManagerScreen({super.key, required this.hospital});

  @override
  State<HospitalManagerScreen> createState() => _HospitalManagerScreenState();
}

class _HospitalManagerScreenState extends State<HospitalManagerScreen> {
  late bool offerInjuryHealing;
  late bool offerOrthopedicServices;
  late bool offerPerformanceTherapy;
  late bool offerDiseaseTherapy;

  Map<String, dynamic>? _lastSyncedHospitalData;

  // ==================== EFFICIENT DOCTORS RESEARCH STATE ====================
  Timer? _researchTimer;
  bool _isStartingResearch = false;

  // Track starting research for performance therapies (to disable tap)
  bool _isStartingStaminaResearch = false;
  bool _isStartingConstitutionResearch = false;

  // Track selected Epinephrine image for visual stacking
  String? _selectedEpinephrineAsset;

  // ==================== NEW: Price controllers for performance services ====================
  final TextEditingController _staminaCostController = TextEditingController();
  final TextEditingController _constitutionCostController = TextEditingController();

  // Helper: Get quality number from asset path (e.g. "assets/epinephrine_5.png" → 5)
int _getQualityFromAsset(String assetPath) {
  final match = RegExp(r'epinephrine_(\d)').firstMatch(assetPath);
  return int.tryParse(match?.group(1) ?? '1') ?? 1;
}

// Helper: Get how many Epinephrine solutions of this quality the player has
int _getEpinephrineQuantity(int quality) {
  final inventory = SocketService().statsNotifier.value['inventory'] as List<dynamic>? ?? [];
  return inventory
      .where((item) => item['name'] == 'Epinephrine solution' && (item['quality'] as num?)?.toInt() == quality)
      .length;
}

  @override
  void initState() {
    super.initState();
    _syncFromHospitalData(widget.hospital);
    _startResearchTimer();

    SocketService().socket?.on('research-result', _onResearchResult);
  }

  @override
  void dispose() {
    // ✅ ADD THIS LINE - Cleanly remove the listener
    SocketService().socket?.off('research-result', _onResearchResult);
    
    _researchTimer?.cancel();
    _staminaCostController.dispose();
    _constitutionCostController.dispose();
    super.dispose();
  }

  void _onResearchResult(dynamic data) {
    if (!mounted) return;

    if (data is Map<String, dynamic>) {
      final bool success = data['success'] ?? false;
      final String message = data['message'] ?? 'Research action completed.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        setState(() {
          _isStartingResearch = false;
          _isStartingStaminaResearch = false;
          _isStartingConstitutionResearch = false;
        });
      }
    }
  }

  void _startResearchTimer() {
    _researchTimer?.cancel();
    _researchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final docId = widget.hospital['docId'];
      if (docId != null) {
        final fresh = SocketService().hospitalOwnershipNotifier.value[docId] 
            as Map<String, dynamic>? ?? widget.hospital;

        // === AUTO-CLAIM EFFICIENT DOCTORS ===
        final int? efficientEndTime = fresh['efficientDoctorsResearchEndTime'] as int?;
        if (efficientEndTime != null && efficientEndTime > 0 && efficientEndTime <= SocketService().currentServerTime) {
            SocketService().socket?.emit('claim-efficient-doctors-research', {'hospitalDocId': docId});
            print('[RESEARCH] Auto-claimed Efficient Doctors research for $docId');
        }

        // === NEW: AUTO-CLAIM ENHANCED STAMINA ===
        final int? staminaEndTime = fresh['enhancedStaminaResearchEndTime'] as int?;
        if (staminaEndTime != null && staminaEndTime > 0 && staminaEndTime <= SocketService().currentServerTime) {
            SocketService().socket?.emit('claim-enhanced-stamina-research', {'hospitalDocId': docId});
            print('[RESEARCH] Auto-claimed Enhanced Stamina research for $docId');
        }

        // === NEW: AUTO-CLAIM ENHANCED CONSTITUTION ===
        final int? constitutionEndTime = fresh['enhancedConstitutionResearchEndTime'] as int?;
        if (constitutionEndTime != null && constitutionEndTime > 0 && constitutionEndTime <= SocketService().currentServerTime) {
            SocketService().socket?.emit('claim-enhanced-constitution-research', {'hospitalDocId': docId});
            print('[RESEARCH] Auto-claimed Enhanced Constitution research for $docId');
        }
      }

      setState(() {}); // Refresh UI for countdowns
    });
  }

  // ==================== Sync local state from hospital data (now includes duration + research + new costs) ====================
  void _syncFromHospitalData(Map<String, dynamic> hospitalData) {
    offerInjuryHealing = hospitalData['offerInjuryHealing'] ?? false;
    offerOrthopedicServices = hospitalData['offerOrthopedicServices'] ?? false;
    offerPerformanceTherapy = hospitalData['offerPerformanceTherapy'] ?? false;
    offerDiseaseTherapy = hospitalData['offerDiseaseTherapy'] ?? false;

    // Load stamina and constitution prices
    final int staminaCost = (hospitalData['customStaminaCost'] as num?)?.toInt() ?? 150;
    _staminaCostController.text = staminaCost.toString();

    final int constitutionCost = (hospitalData['customConstitutionCost'] as num?)?.toInt() ?? 150;
    _constitutionCostController.text = constitutionCost.toString();

    // ==================== NEW: Load saved Epinephrine quality ====================
    final int? savedQuality = (hospitalData['selectedEpinephrineQuality'] as num?)?.toInt();
    if (savedQuality != null && savedQuality >= 1 && savedQuality <= 5) {
      _selectedEpinephrineAsset = 'assets/epinephrine_$savedQuality.png';
    } else {
      _selectedEpinephrineAsset = null;
    }
  }

  void _saveSwitchState(String field, bool value) {
    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-service', {
      'docId': docId,
      'field': field,
      'value': value,
    });
  }

  // ==================== FIXED: Now accepts the cost from the child widget ====================
  void _updateHealCost(int newCost) {
    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-heal-cost', {
      'docId': docId,
      'newCost': newCost,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Heal cost updated to \$$newCost')),
    );
  }

  // ==================== NEW: Update Healing Duration on Server ====================
  void _updateHealingDuration(int seconds) {
    final docId = widget.hospital['docId'];
    if (docId == null) return;

    final durationMs = seconds * 1000;

    SocketService().socket?.emit('update-hospital-healing-duration', {
      'docId': docId,
      'healingDurationMs': durationMs,
    });

    // NOTE: Removed setState for _healingTimeInSeconds (no longer exists in parent - child manages it locally)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Healing time updated to ${_formatTime(seconds)}')),
    );
  }

  // ==================== NEW: Update Stamina Cost ====================
  void _updateStaminaCost() {
    final newCost = int.tryParse(_staminaCostController.text);
    if (newCost == null || newCost < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid cost ≥ \$1')),
      );
      return;
    }

    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-stamina-cost', {
      'docId': docId,
      'newCost': newCost,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stamina price updated to \$$newCost')),
    );
  }

  // ==================== NEW: Update Constitution Cost ====================
  void _updateConstitutionCost() {
    final newCost = int.tryParse(_constitutionCostController.text);
    if (newCost == null || newCost < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid cost ≥ \$1')),
      );
      return;
    }

    final docId = widget.hospital['docId'];
    if (docId == null) return;

    SocketService().socket?.emit('update-hospital-constitution-cost', {
      'docId': docId,
      'newCost': newCost,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Constitution price updated to \$$newCost')),
    );
  }
  
  // ==================== Get list of currently active services ====================
  List<String> _getActiveServices() {
    final List<String> active = [];
    if (offerInjuryHealing) active.add('Injury Healing');
    if (offerOrthopedicServices) active.add('Orthopedic Services');
    if (offerPerformanceTherapy) active.add('Performance enhancing');
    if (offerDiseaseTherapy) active.add('Disease Therapy');
    return active;
  }

  // ==================== Dynamic bottom section (now receives fresh data) ====================
  Widget _buildBottomSection(Map<String, dynamic> hospitalData) {
    final activeServices = _getActiveServices();

    if (activeServices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_hospital, size: 120, color: Colors.purple[300]),
              const SizedBox(height: 24),
              Text(
                '${hospitalData['location']} Hospital #${hospitalData['index']}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _showReleaseConfirmation,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: Colors.red[700],
                  ),
                  child: const Text(
                    'Release Hospital',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return DefaultTabController(
        length: activeServices.length,
        child: Column(
          children: [
            TabBar(
              isScrollable: activeServices.length > 2,
              tabs: activeServices.map((service) => Tab(text: service)).toList(),
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
            ),
            Expanded(
              child: TabBarView(
                children: activeServices.map((service) {
                  return _buildServiceTab(service, hospitalData);
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ==================== Content for each service tab (now receives fresh data) ====================
  Widget _buildServiceTab(String serviceName, Map<String, dynamic> hospitalData) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
          child: Column(
        children: [
          if (serviceName == 'Injury Healing')
            InjuryHealingTabContent(
              hospital: hospitalData, // Pass fresh data so child stays in sync
              isStartingResearch: _isStartingResearch,
              onUpdateHealCost: _updateHealCost,
              onUpdateHealingDuration: _updateHealingDuration,
              onStartEfficientDoctorsResearch: () {
                final docId = hospitalData['docId'];
                if (docId != null) {
                  setState(() => _isStartingResearch = true);
                  SocketService().socket?.emit('start-efficient-doctors-research', {
                    'hospitalDocId': docId,
                  });
                }
              },
            ),

          // ==================== NEW: PERFORMANCE THERAPY RESEARCH CARDS ====================
          if (serviceName == 'Performance enhancing')
            Column(
              children: [
                // ========== ENHANCED STAMINA CARD ==========
                ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: SocketService().hospitalOwnershipNotifier,
                  builder: (context, ownership, _) {
                    final docId = hospitalData['docId'] ?? ''; // Use passed fresh data
                    final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? hospitalData;

                    final bool hasResearched = freshHospital['hasEnhancedStamina'] == true;
                    final int? researchEndTime = freshHospital['enhancedStaminaResearchEndTime'] as int?;
                    final bool isResearching = researchEndTime != null && researchEndTime > SocketService().currentServerTime;

                    int remainingSeconds = 0;
                    if (isResearching) {
                      remainingSeconds = ((researchEndTime - SocketService().currentServerTime) / 1000).ceil().clamp(0, 30);
                    }

                    final bool offerEnabled = freshHospital['offerEnhancedStamina'] == true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      color: hasResearched ? Colors.green[900] : Colors.grey[850],
                      child: InkWell(
                        onTap: (hasResearched || isResearching || _isStartingStaminaResearch)
                          ? null
                          : () {
                              final docId = hospitalData['docId'];
                              if (docId != null) {
                                setState(() => _isStartingStaminaResearch = true);

                                SocketService().socket?.emit('start-enhanced-stamina-research', {
                                  'hospitalDocId': docId,
                                });
                              }
                            },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    hasResearched ? Icons.check_circle : Icons.science,
                                    color: hasResearched ? Colors.greenAccent : Colors.amber,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Enhanced Stamina',
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  if (isResearching)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'RESEARCHING... ${remainingSeconds}s',
                                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    )
                                  else if (hasResearched)
                                    Switch(
                                        value: offerEnabled,
                                        onChanged: (bool newValue) {
                                          setState(() {
                                            // Update local for immediate feedback
                                          });
                                          _saveSwitchState('offerEnhancedStamina', newValue);
                                        },
                                        activeColor: Colors.greenAccent,
                                      )
                                  else
                                    const Text('\$1000 • 30s', style: TextStyle(color: Colors.amber)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                hasResearched
                                    ? 'Effect: Unlocks enhanced stamina therapy for patients (toggle below to enable).'
                                    : 'Research this to unlock Enhanced Stamina therapy options for your hospital.',
                                style: TextStyle(fontSize: 15, color: hasResearched ? Colors.greenAccent : Colors.white70),
                              ),
                              if (!hasResearched && !isResearching)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Tap to begin research →',
                                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                                  ),
                                ),

                          
                              // ==================== NEW: Stamina Price Editor ====================
if (hasResearched)
  Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showEpinephrineSelectionDialog(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Base empty image
              Image.asset(
                'assets/epinephrine_empty.png',
                height: 90,
                width: 90,
                fit: BoxFit.contain,
              ),

              // Overlay selected quality image + quantity badge
              if (_selectedEpinephrineAsset != null)
                Stack(
                  children: [
                    Image.asset(
                      _selectedEpinephrineAsset!,
                      height: 72,
                      width: 72,
                      fit: BoxFit.contain,
                    ),

                    // Quantity badge on bottom left
                    Positioned(
                      bottom: 2,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'x${_getEpinephrineQuantity(_getQualityFromAsset(_selectedEpinephrineAsset!))}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Tap to select Epinephrine solution',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 10),

        const Text(
          'Stamina Service Price (paid to you)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _staminaCostController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixText: '\$',
                  border: OutlineInputBorder(),
                  hintText: 'Enter price',
                  fillColor: Colors.white,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _updateStaminaCost,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // ========== ENHANCED CONSTITUTION CARD ==========
                ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: SocketService().hospitalOwnershipNotifier,
                  builder: (context, ownership, _) {
                    final docId = hospitalData['docId'] ?? ''; // Use passed fresh data
                    final freshHospital = (ownership[docId] as Map<String, dynamic>?) ?? hospitalData;

                    final bool hasResearched = freshHospital['hasEnhancedConstitution'] == true;
                    final int? researchEndTime = freshHospital['enhancedConstitutionResearchEndTime'] as int?;
                    final bool isResearching = researchEndTime != null && researchEndTime > SocketService().currentServerTime;

                    int remainingSeconds = 0;
                    if (isResearching) {
                      remainingSeconds = ((researchEndTime - SocketService().currentServerTime) / 1000).ceil().clamp(0, 30);
                    }

                    final bool offerEnabled = freshHospital['offerEnhancedConstitution'] == true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      color: hasResearched ? Colors.green[900] : Colors.grey[850],
                      child: InkWell(
                        onTap: (hasResearched || isResearching || _isStartingConstitutionResearch)
                          ? null
                          : () {
                              final docId = hospitalData['docId'];
                              if (docId != null) {
                                setState(() => _isStartingConstitutionResearch = true);

                                SocketService().socket?.emit('start-enhanced-constitution-research', {
                                  'hospitalDocId': docId,
                                });
                              }
                            },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    hasResearched ? Icons.check_circle : Icons.science,
                                    color: hasResearched ? Colors.greenAccent : Colors.amber,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Enhanced Constitution',
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  if (isResearching)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'RESEARCHING... ${remainingSeconds}s',
                                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    )
                                  else if (hasResearched)
                                    const Text('✅ RESEARCHED', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))
                                  else
                                    const Text('\$1000 • 30s', style: TextStyle(color: Colors.amber)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                hasResearched
                                    ? 'Effect: Unlocks enhanced constitution therapy for patients (toggle below to enable).'
                                    : 'Research this to unlock Enhanced Constitution therapy options for your hospital.',
                                style: TextStyle(fontSize: 15, color: hasResearched ? Colors.greenAccent : Colors.white70),
                              ),
                              if (!hasResearched && !isResearching)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Tap to begin research →',
                                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                                  ),
                                ),

                              // NEW: Toggle switch when researched (off by default)
                              if (hasResearched)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Enable Enhanced Constitution',
                                        style: TextStyle(fontSize: 16, color: Colors.white70),
                                      ),
                                      Switch(
                                        value: offerEnabled,
                                        onChanged: (bool newValue) {
                                          setState(() {
                                            // Update local for immediate feedback
                                          });
                                          _saveSwitchState('offerEnhancedConstitution', newValue);
                                        },
                                        activeColor: Colors.greenAccent,
                                      ),
                                    ],
                                  ),
                                ),

                              // ==================== NEW: Constitution Price Editor ====================
                              if (hasResearched)
                                Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Constitution Service Price (paid to you)',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _constitutionCostController,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                prefixText: '\$',
                                                border: OutlineInputBorder(),
                                                hintText: 'Enter price',
                                                fillColor: Colors.white,
                                                filled: true,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton(
                                            onPressed: _updateConstitutionCost,
                                            child: const Text('Save'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),
              ],
            ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showReleaseConfirmation,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: Colors.red[700],
              ),
              child: const Text(
                'Release Hospital',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    )
    );
  }

  // ==================== Helper to format seconds into MM:SS ====================
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

// ==================== NEW: Epinephrine Selection Dialog (Grouped by Quality) ====================
void _showEpinephrineSelectionDialog() {
  final inventory = SocketService().statsNotifier.value['inventory'] as List<dynamic>? ?? [];

  // Filter Epinephrine solutions
  final epinephrineItems = inventory
      .where((item) => item['name'] == 'Epinephrine solution')
      .toList();

  if (epinephrineItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You have no Epinephrine solutions in your inventory.')),
    );
    return;
  }

  // Group by quality
  final Map<int, int> qualityCount = {};
  for (var item in epinephrineItems) {
    final quality = (item['quality'] as num?)?.toInt() ?? 1;
    qualityCount[quality] = (qualityCount[quality] ?? 0) + 1;
  }

  // Sort qualities from 5 to 1
  final sortedQualities = qualityCount.keys.toList()
    ..sort((a, b) => b.compareTo(a));

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Select Epinephrine Solution'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: sortedQualities.length,
          itemBuilder: (context, index) {
            final quality = sortedQualities[index];
            final count = qualityCount[quality]!;

            return ListTile(
              leading: Image.asset(
                'assets/epinephrine_$quality.png',
                width: 40,
                height: 40,
              ),
              title: Text('Quality $quality'),
              subtitle: Text('Value: \$${quality >= 4 ? 30 : 20}   •   You have: $count'),
              onTap: () {
                final docId = widget.hospital['docId'];
                if (docId != null) {
                  // Only tell the server — do NOT update locally here
                  SocketService().socket?.emit('set-selected-epinephrine-quality', {
                    'hospitalDocId': docId,
                    'quality': quality,
                  });
                }
                Navigator.pop(context);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
  onPressed: () {
    final docId = widget.hospital['docId'];
    if (docId != null) {
      // Only tell the server — do NOT update locally here
      SocketService().socket?.emit('set-selected-epinephrine-quality', {
        'hospitalDocId': docId,
        'quality': null,
      });
    }
    Navigator.pop(context);
  },
  child: const Text('Clear Selection'),
),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

  // ==================== Release confirmation dialog ====================
  Future<void> _showReleaseConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Hospital'),
        content: const Text(
          'Are you sure you want to release this hospital?\n\n'
          'It will no longer belong to you and can be claimed by any other player.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Release Hospital'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      SocketService().socket?.emit('release-hospital', {
        'docId': widget.hospital['docId'],
      });

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hospital released successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String location = widget.hospital['location'] ?? 'Unknown';
    final int index = widget.hospital['index'] ?? 0;
    final String hospitalName = '$location Hospital #$index';

    return Scaffold(
      appBar: StatusAppBar(
        title: hospitalName,
        statsNotifier: SocketService().statsNotifier,
        time: 'Live',
        onMenuPressed: () => Navigator.pop(context),
      ),
      body: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: SocketService().hospitalOwnershipNotifier,
        builder: (context, ownership, child) {
          final String docId = widget.hospital['docId'] ?? '';
          final Map<String, dynamic> freshHospital = 
              (ownership[docId] as Map<String, dynamic>?) ?? widget.hospital;

          // ==================== ONLY sync if something important changed ====================
          final bool shouldSync = _lastSyncedHospitalData == null ||
            freshHospital['offerInjuryHealing'] != _lastSyncedHospitalData!['offerInjuryHealing'] ||
            freshHospital['offerOrthopedicServices'] != _lastSyncedHospitalData!['offerOrthopedicServices'] ||
            freshHospital['offerPerformanceTherapy'] != _lastSyncedHospitalData!['offerPerformanceTherapy'] ||
            freshHospital['offerDiseaseTherapy'] != _lastSyncedHospitalData!['offerDiseaseTherapy'] ||
            freshHospital['hasEnhancedStamina'] != _lastSyncedHospitalData!['hasEnhancedStamina'] ||
            freshHospital['enhancedStaminaResearchEndTime'] != _lastSyncedHospitalData!['enhancedStaminaResearchEndTime'] ||
            freshHospital['hasEnhancedConstitution'] != _lastSyncedHospitalData!['hasEnhancedConstitution'] ||
            freshHospital['enhancedConstitutionResearchEndTime'] != _lastSyncedHospitalData!['enhancedConstitutionResearchEndTime'] ||
            freshHospital['customStaminaCost'] != _lastSyncedHospitalData!['customStaminaCost'] ||
            freshHospital['customConstitutionCost'] != _lastSyncedHospitalData!['customConstitutionCost'] ||
            freshHospital['selectedEpinephrineQuality'] != _lastSyncedHospitalData!['selectedEpinephrineQuality'];

          if (shouldSync) {
            _lastSyncedHospitalData = Map<String, dynamic>.from(freshHospital);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _syncFromHospitalData(freshHospital);
                });
              }
            });
          }

          return Column(
            children: [
              // ==================== 2x2 SWITCHES ====================
ValueListenableBuilder<Map<String, dynamic>>(
  valueListenable: SocketService().statsNotifier,
  builder: (context, stats, _) {
    final int balance = (stats['balance'] ?? 0).toInt();
    final bool canAffordMaintenance = balance >= 10;
    final bool isInjuryHealingCurrentlyOn = freshHospital['offerInjuryHealing'] ?? false;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 6,
          childAspectRatio: 2.8,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildSwitch(
              "Injury healing",
              offerInjuryHealing,
              (v) {
                setState(() => offerInjuryHealing = v);
                _saveSwitchState('offerInjuryHealing', v);
              },
              enabled: isInjuryHealingCurrentlyOn || canAffordMaintenance,
            ),
            _buildSwitch("Orthopedic services", offerOrthopedicServices, (v) {
              setState(() => offerOrthopedicServices = v);
              _saveSwitchState('offerOrthopedicServices', v);
            }),
            _buildSwitch("Performance enhancing", offerPerformanceTherapy, (v) {
              setState(() => offerPerformanceTherapy = v);
              _saveSwitchState('offerPerformanceTherapy', v);
            }),
            _buildSwitch("Disease therapy", offerDiseaseTherapy, (v) {
              setState(() => offerDiseaseTherapy = v);
              _saveSwitchState('offerDiseaseTherapy', v);
            }),
          ],
        ),
      ),
    );
  },
),

              const Divider(height: 1),

              // ==================== DYNAMIC BOTTOM SECTION ====================
              Expanded(
                child: _buildBottomSection(freshHospital), // Pass fresh data down
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitch(
    String label, 
    bool value, 
    Function(bool) onChanged, {
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.grey[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: enabled ? Colors.black : Colors.grey[600],
          ),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
