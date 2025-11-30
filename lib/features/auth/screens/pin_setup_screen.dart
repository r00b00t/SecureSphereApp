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
        
        // Show success message safely using ScaffoldMessenger
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              try {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Success! 6-digit PIN has been set successfully'),
                    backgroundColor: Colors.green.withOpacity(0.9),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
              }
            }
          });
        }
        
        
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

      // Check if we can navigate back normally
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop(true);
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
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPin = _isConfirming ? _confirmPin : _firstPin;
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 600;
    final isSmallScreen = screenSize.height < 700;
    
    return PopScope(
      canPop: widget.isOptional, // Allow back only if PIN setup is optional
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!widget.isOptional) {
          // PIN setup is required, show warning
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('PIN Required - Please complete PIN setup to continue'),
                backgroundColor: Colors.orange.withOpacity(0.8),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
          }
        }
      },
      child: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isConfirming ? _resetPin : () => Navigator.of(context).pop(),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 500 : double.infinity,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      SizedBox(height: isSmallScreen ? 8 : 16),
              
                      // Security icon
                      Container(
                        width: isSmallScreen ? 80 : 100,
                        height: isSmallScreen ? 80 : 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.primaryColor,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(isSmallScreen ? 20 : 25),
                          boxShadow: [
                            BoxShadow(
                              color: theme.primaryColor.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.security,
                          size: isSmallScreen ? 40 : 50,
                          color: Colors.white,
                        ),
                      ),
                      
                      SizedBox(height: isSmallScreen ? 16 : 24),
              
                      // Title
                      Text(
                        widget.title ?? (_isConfirming ? 'Confirm your PIN' : 'Set up your PIN'),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 22 : 26,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      
                      // Description
                      Text(
                        _isConfirming 
                            ? 'Please re-enter your 6-digit PIN to confirm'
                            : 'Create a 6-digit PIN to secure your app',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      SizedBox(height: isSmallScreen ? 20 : 32),
              
                      // PIN dots indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(6, (index) {
                          final isFilled = index < currentPin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 6 : 8),
                            width: isSmallScreen ? 16 : 20,
                            height: isSmallScreen ? 16 : 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled 
                                  ? theme.primaryColor 
                                  : theme.colorScheme.outline.withOpacity(0.2),
                              border: Border.all(
                                color: isFilled 
                                    ? theme.primaryColor 
                                    : theme.primaryColor.withOpacity(0.4),
                                width: 2,
                              ),
                              boxShadow: isFilled ? [
                                BoxShadow(
                                  color: theme.primaryColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ] : [],
                            ),
                          );
                        }),
                      ),
                      
                      SizedBox(height: isSmallScreen ? 12 : 20),
              
                      // Error message
                      Container(
                        height: isSmallScreen ? 35 : 40,
                        alignment: Alignment.center,
                        child: _errorMessage != null
                            ? Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isSmallScreen ? 12 : 16,
                                  vertical: isSmallScreen ? 6 : 8,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.colorScheme.error.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontSize: isSmallScreen ? 12 : 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : null,
                      ),
                      
                      SizedBox(height: isSmallScreen ? 12 : 20),
                      
                      // PIN keypad with actions
                      _buildKeypad(theme, isSmallScreen, isDesktop),
                      
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      
                      // Bottom actions
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Show confirm button when both PINs are complete and match
                          if (_isConfirming && _confirmPin.length == 6 && _firstPin == _confirmPin)
                            Column(
                              children: [
                                SizedBox(
                                  width: 200,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _verifyPins,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 6,
                                      shadowColor: theme.primaryColor.withOpacity(0.4),
                                    ),
                                    child: _isLoading 
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check_circle, size: 22),
                                              SizedBox(width: 8),
                                              Text(
                                                'Confirm PIN',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _resetPin,
                                  child: const Text(
                                    'Start over',
                                    style: TextStyle(fontSize: 14),
                                  ),
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
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ), // Close SafeArea
    ), // Close Scaffold
    ); // Close PopScope
  }

  Widget _buildKeypad(ThemeData theme, bool isSmallScreen, bool isDesktop) {
    final buttonSize = isSmallScreen ? 60.0 : (isDesktop ? 80.0 : 70.0);
    final spacing = isSmallScreen ? 8.0 : 12.0;
    
    return Container(
      constraints: BoxConstraints(maxWidth: isDesktop ? 400 : 320),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('1', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('2', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('3', theme, buttonSize, isSmallScreen),
            ],
          ),
          SizedBox(height: spacing),
          
          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('4', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('5', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('6', theme, buttonSize, isSmallScreen),
            ],
          ),
          SizedBox(height: spacing),
          
          // Row 3: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('7', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('8', theme, buttonSize, isSmallScreen),
              _buildKeypadButton('9', theme, buttonSize, isSmallScreen),
            ],
          ),
          SizedBox(height: spacing),
          
          // Row 4: empty, 0, backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(width: buttonSize, height: buttonSize),
              _buildKeypadButton('0', theme, buttonSize, isSmallScreen),
              _buildBackspaceButton(theme, buttonSize, isSmallScreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String number, ThemeData theme, double size, bool isSmallScreen) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _onNumberPressed(number),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surface.withOpacity(0.8),
            ],
          ),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            number,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: isSmallScreen ? 24 : 28,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(ThemeData theme, double size, bool isSmallScreen) {
    return GestureDetector(
      onTap: _isLoading ? null : _onBackspacePressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          Icons.backspace_outlined,
          color: theme.colorScheme.error,
          size: isSmallScreen ? 24 : 28,
        ),
      ),
    );
  }
}
