// lib/widgets/login_widget.dart
import 'package:flutter/material.dart';
import '../ui/pallet.dart';
import '../wishnode_api.dart';
import '../utils/log.dart';

class LoginWidget extends StatefulWidget {
  final VoidCallback onClose;
  final Function(String userId, String token) onLoginSuccess;
  final WishnodeApi api;
  final String? currentAnonUserId; // Pass in the current anon user id

  const LoginWidget({
    Key? key,
    required this.onClose,
    required this.onLoginSuccess,
    required this.api,
    this.currentAnonUserId,
  }) : super(key: key);

  @override
  State<LoginWidget> createState() => _LoginWidgetState();
}

class _LoginWidgetState extends State<LoginWidget> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLogin = true; // true = login, false = register
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      Map<String, dynamic> result;
      
      if (_isLogin) {
        result = await widget.api.login(email, password);
      } else {
        // Pass the current anon user id when registering to claim the account
        result = await widget.api.register(email, password, anonUserId: widget.currentAnonUserId);
      }

      final userId = result['user_id']?.toString();
      final token = result['token']?.toString();

      if (userId != null && token != null) {
        widget.onLoginSuccess(userId, token);
      } else {
        throw Exception('Invalid response from server');
      }
    } catch (e) {
      Log.d('[LoginWidget] error: $e');
      setState(() {
        if (e is ApiException) {
          _errorMessage = e.message;
        } else {
          _errorMessage = _isLogin ? 'Login failed' : 'Registration failed';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: MediaQuery.of(context).size.width > 600 ? 400 : null,
            margin: EdgeInsets.symmetric(horizontal: 24),
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Palette.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isLogin ? 'Welcome back' : 'Create account',
                        style: TextStyle(
                          color: Palette.ourWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Palette.dampTitles),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 24),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: Palette.ourWhite),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: Palette.dampTitles),
                      filled: true,
                      fillColor: Palette.darkest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Palette.signatureGreen),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email is required';
                      }
                      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!emailRegex.hasMatch(value)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),

                  SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: TextStyle(color: Palette.ourWhite),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: TextStyle(color: Palette.dampTitles),
                      filled: true,
                      fillColor: Palette.darkest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Palette.signatureGreen),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Palette.dampTitles,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (!_isLogin && value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),

                  // Error message
                  if (_errorMessage != null) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: 24),

                  // Submit button
                  ElevatedButton(
                    onPressed: _loading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Palette.signatureGreen,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: _loading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.black),
                            ),
                          )
                        : Text(
                            _isLogin ? 'Log in' : 'Create account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),

                  SizedBox(height: 16),

                  // Toggle between login/register
                  TextButton(
                    onPressed: _toggleMode,
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(color: Palette.dampTitles),
                        children: [
                          TextSpan(
                            text: _isLogin
                                ? "Don't have an account? "
                                : 'Already have an account? ',
                          ),
                          TextSpan(
                            text: _isLogin ? 'Sign up' : 'Log in',
                            style: TextStyle(
                              color: Palette.signatureGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Skip button (continue as guest)
                  SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onClose,
                    child: Text(
                      'Continue as guest',
                      style: TextStyle(
                        color: Palette.dampTitles,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}