import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;

  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _usernameCtrl;
  String _dob = 'Add a DOB';
  String _gender = 'Prefer not to say';
  Color _territoryColor = Colors.blue;

  late final List<Color> _colorOptions = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Theme.of(context).colorScheme.primary,
    Theme.of(context).colorScheme.error,
    Theme.of(context).colorScheme.secondary,
    AppColors.gold,
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final uid = user?.uid;
    if (uid == null) {
      _setDefaultFields();
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _firstNameCtrl = TextEditingController(text: data['firstName'] ?? '');
        _lastNameCtrl = TextEditingController(text: data['lastName'] ?? '');
        _usernameCtrl = TextEditingController(text: data['username'] ?? '');
        _dob = data['dob'] ?? 'Add a DOB';
        _gender = data['gender'] ?? 'Prefer not to say';
        if (data['territoryColor'] != null) {
          _territoryColor = Color(data['territoryColor']);
        }
      } else {
        _setDefaultFields();
      }
    } catch (_) {
      _setDefaultFields();
    }
    setState(() => _isLoading = false);
  }

  void _setDefaultFields() {
    final email = user?.email?.split('@').first ?? '';
    final parts = email.split('.');
    _firstNameCtrl = TextEditingController(text: parts.isNotEmpty ? parts[0].toUpperCase() : '');
    _lastNameCtrl = TextEditingController(text: parts.length > 1 ? parts[1].toUpperCase() : '');
    _usernameCtrl = TextEditingController(text: email.toUpperCase());
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(
            primary: Theme.of(context).colorScheme.primary,
            surface: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dob = '${picked.day}/${picked.month}/${picked.year}');
    }
  }

  void _pickGender() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Male', 'Female', 'Non-binary', 'Prefer not to say']
              .map((g) => ListTile(
                    title: Text(g, style: const TextStyle(color: Colors.white)),
                    trailing: _gender == g
                        ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() => _gender = g);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Choose Territory Colour', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _colorOptions.map((c) => GestureDetector(
                onTap: () {
                  setState(() => _territoryColor = c);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(12),
                    border: _territoryColor == c
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    final uid = user?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('Users').doc(uid).set({
        'firstName': _firstNameCtrl.text,
        'lastName': _lastNameCtrl.text,
        'username': _usernameCtrl.text,
        'dob': _dob,
        'gender': _gender,
        'territoryColor': _territoryColor.toARGB32(),
      }, SetOptions(merge: true));
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }
    
    // Compute initials
    String initials = 'U';
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isNotEmpty && last.isNotEmpty) {
      initials = '${first[0]}${last[0]}'.toUpperCase();
    } else if (first.isNotEmpty) {
      initials = first[0].toUpperCase();
    } else if (_usernameCtrl.text.trim().isNotEmpty) {
      final uname = _usernameCtrl.text.trim();
      initials = uname.substring(0, uname.length >= 2 ? 2 : 1).toUpperCase();
    } else {
      final name = user?.email?.split('@').first ?? 'U';
      initials = name.isNotEmpty ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase() : 'U';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('PROFILE', style: GoogleFonts.orbitron(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: Text('Done', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile picture
            Center(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _firstNameCtrl,
                builder: (context, _, __) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _lastNameCtrl,
                    builder: (context, _, __) {
                      final f = _firstNameCtrl.text.trim();
                      final l = _lastNameCtrl.text.trim();
                      String liveInitials = initials;
                      if (f.isNotEmpty && l.isNotEmpty) {
                        liveInitials = '${f[0]}${l[0]}'.toUpperCase();
                      } else if (f.isNotEmpty) {
                        liveInitials = f[0].toUpperCase();
                      }
                      return CircleAvatar(
                        radius: 48,
                        backgroundColor: Theme.of(context).cardColor,
                        child: Text(
                          liveInitials,
                          style: GoogleFonts.orbitron(fontSize: 28, color: Theme.of(context).colorScheme.primary),
                        ),
                      );
                    }
                  );
                }
              ),
            ),
            const SizedBox(height: 32),

            // Name fields
            Row(
              children: [
                Expanded(child: _buildField('First Name', _firstNameCtrl)),
                const SizedBox(width: 16),
                Expanded(child: _buildField('Last Name', _lastNameCtrl)),
              ],
            ),
            const SizedBox(height: 16),
            _buildField('Username', _usernameCtrl),
            const SizedBox(height: 16),

            // DOB & Gender
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: _buildReadOnlyField('Date of Birth', _dob),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickGender,
                    child: _buildReadOnlyField('Gender', _gender),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Territory color & Current skin
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('Territory colour', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 16),
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: _territoryColor,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: _territoryColor.withValues(alpha: 0.5), blurRadius: 10)],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: _showColorPicker,
                        child: Text('Change Colour', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('Current skin', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 16),
                      Container(
                        width: 80, height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                        ),
                        alignment: Alignment.center,
                        child: Text('No skin', style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 12)),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Skin shop coming soon!')),
                          );
                        },
                        child: Text('Change skin', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}
