import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/security_service.dart';

class PinSetupScreen extends StatefulWidget {
  final bool isOptional;
  final String? title;
  final VoidCallback? onSkip;
  final VoidCallback? onComplete;

  const PinSetupScreen({
    super.key,
    this.isOptional = false,
    this.title,
    this.onSkip,
    this.onComplete,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final SecurityService _securityService = Get.find<SecurityService>();
  
  String _firstPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isLoading = false;
  String? _errorMessage;

  void _onNumberPressed(String number) {
    if (_isConfirming) {
      if (_confirmPin.length < 6) {
        setState(() {
          _confirmPin += number;
          _errorMessage = null;
        });
        
        // Don't auto-verify, let user confirm manually
      }
    } else {
      if (_firstPin.length < 6) {
        setState(() {
          _firstPin += number;
          _errorMessage = null;
        });
        
        // Move to confirmation when exactly 6 digits are entered
        if (_firstPin.length == 6) {
          setState(() {
            _isConfirming = true;
          });
        }
      }
    }
  }

  void _onBackspacePressed() {
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
          _errorMessage = null;
        });
      }
    } else {
      if (_firstPin.isNotEmpty) {
        setState(() {
          _firstPin = _firstPin.substring(0, _firstPin.length - 1);
          _errorMessage = null;
        });
      }
    }
  }

  Future<void> _verifyPins() async {
    // Ensure both PINs are exactly 6 digits
    if (_firstPin.length != 6 || _confirmPin.length != 6) {
      setState(() {
        _errorMessage = 'PIN must be exactly 6 digits.';
        _firstPin = '';
        _confirmPin = '';
        _isConfirming = false;
        _isLoading = false;
      });
      return;
    }

    if (_firstPin != _confirmPin) {
      setState(() {
        _errorMessage = 'PINs do not match. Please try again.';
        _firstPin = '';
        _confirmPin = '';
        _isConfirming = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await _securityService.setPinCode(_firstPin).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          return false;
        },
      );
      
      if (success) {
        
        // Show success message immediately
        Get.snackbar(
          'Success ',
          '6-digit PIN has been set successfully',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.withOpacity(0.9),
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
        
        
        // Delay navigation to next frame to ensure UI updates complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _attemptScreenClose();
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to set PIN. Please try again.';
          _firstPin = '';
          _confirmPin = '';
          _isConfirming = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _firstPin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
    } finally {
      // Always reset loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _resetPin() {
    setState(() {
      _firstPin = '';
      _confirmPin = '';
      _isConfirming = false;
      _errorMessage = null;
    });
  }

  String _getStatusMessage() {
    if (!_isConfirming) {
      return 'Step 1 of 2: Create PIN';
    }
    
    if (_confirmPin.length < 6) {
      return 'Step 2 of 2: Confirm PIN';
    }
    
    if (_firstPin == _confirmPin) {
      return 'Ready to save PIN';
    } else {
      return 'PINs do not match. Try again.';
    }
  }

  Color _getStatusColor(ThemeData theme) {
    if (!_isConfirming || _confirmPin.length < 6) {
      return theme.colorScheme.onSurface.withOpacity(0.6);
    }
    
    if (_firstPin == _confirmPin) {
      return theme.primaryColor; // Changed from green to primary color
    } else {
      return Colors.red;
    }
  }

  void _attemptScreenClose() async {
    
    try {
      if (widget.onComplete != null) {
        widget.onComplete!();
        return;
      }

      if (Navigator.canPop(context)) {
        Get.back(result: true);
        return;
      }
      
      // If we can't pop (likely called with Get.offAll), navigate to home
      Get.offAllNamed('/home');
      
    } catch (e) {
      // Last resort - force navigation to home
      Get.offAllNamed('/home');
    }
  }

  void _onSkip() {
    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      Get.back(result: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPin = _isConfirming ? _confirmPin : _firstPin;
    
    return PopScope(
      canPop: widget.isOptional, // Allow back only if PIN setup is optional
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!widget.isOptional) {
          // PIN setup is required, show warning
          Get.snackbar(
            'PIN Required',
            'Please complete PIN setup to continue',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange.withOpacity(0.8),
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      },
      child: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isConfirming ? _resetPin : () => Get.back(),
        ),
        actions: [
          if (widget.isOptional)
            TextButton(
              onPressed: _onSkip,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const SizedBox(height: 16),
              
              // Security icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.security,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Title
              Text(
                widget.title ?? (_isConfirming ? 'Confirm your PIN' : 'Set up your PIN'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              // Description
              Text(
                _isConfirming 
                    ? 'Please re-enter your 6-digit PIN to confirm'
                    : 'Create a 6-digit PIN to secure your app',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // PIN dots indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < currentPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled 
                          ? theme.primaryColor 
                          : theme.colorScheme.outline.withOpacity(0.3),
                      border: Border.all(
                        color: theme.primaryColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                  );
                }),
              ),
              
              const SizedBox(height: 8),
              
              // Error message
              Container(
                height: 30, // Reduced height
                alignment: Alignment.center,
                child: _errorMessage != null
                    ? Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      )
                    : null,
              ),
              
              const SizedBox(height: 8),
              
              // PIN keypad with actions
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _buildKeypad(theme),
                    ),
                    // Bottom actions - moved inside Expanded
                    Container(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show confirm button when both PINs are complete and match
                          if (_isConfirming && _confirmPin.length == 6 && _firstPin == _confirmPin)
                            Column(
                              children: [
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _verifyPins,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                  ),
                                  child: _isLoading 
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Text('Confirm PIN'),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _resetPin,
                                  child: const Text('Start over', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            )
                          else if (_isConfirming)
                            // Show start over button when still entering confirmation PIN
                            TextButton(
                              onPressed: _resetPin,
                              child: const Text('Start over', style: TextStyle(fontSize: 12)),
                            ),
                          
                          // Progress indicator
                          const SizedBox(height: 4),
                          Text(
                            _getStatusMessage(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _getStatusColor(theme),
                              fontSize: 10,
                              fontWeight: FontWeight.normal,
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
      ), // Close SafeArea
    ), // Close Scaffold
    ); // Close PopScope
  }

  Widget _buildKeypad(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start, // Changed from center
        children: [
          // Row 1: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('1', theme),
              _buildKeypadButton('2', theme),
              _buildKeypadButton('3', theme),
            ],
          ),
          const SizedBox(height: 8), // Reduced from 12
          
          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('4', theme),
              _buildKeypadButton('5', theme),
              _buildKeypadButton('6', theme),
            ],
          ),
          const SizedBox(height: 8), // Reduced from 12
          
          // Row 3: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('7', theme),
              _buildKeypadButton('8', theme),
              _buildKeypadButton('9', theme),
            ],
          ),
          const SizedBox(height: 8), // Reduced from 12
          
          // Row 4: empty, 0, backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 50, height: 50), // Reduced empty space
              _buildKeypadButton('0', theme),
              _buildBackspaceButton(theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String number, ThemeData theme) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _onNumberPressed(number),
      child: Container(
        width: 50, // Reduced from 60
        height: 50, // Reduced from 60
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            number,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 20, // Reduced from 24
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(ThemeData theme) {
    return GestureDetector(
      onTap: _isLoading ? null : _onBackspacePressed,
      child: Container(
        width: 50, // Reduced from 60
        height: 50, // Reduced from 60
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.backspace_outlined,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          size: 18, // Reduced from 20
        ),
      ),
    );
  }
}