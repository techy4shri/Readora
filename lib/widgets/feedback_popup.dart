import 'package:flutter/material.dart';

// Enum to represent the different feedback states
enum FeedbackState {
  correct,
  wrong,
  noText,
}

class FeedbackPopup extends StatelessWidget {
  final FeedbackState state;
  final String heading;
  final String message;
  final VoidCallback onContinue;
  final bool showContinueButton;
  final bool showCloseButton;

  const FeedbackPopup({
    Key? key,
    required this.state,
    required this.heading,
    required this.message,
    required this.onContinue,
    this.showContinueButton = true,
    this.showCloseButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Map the state to the appropriate GIF and colors
    String gifAsset;
    Color headerColor;

    switch (state) {
      case FeedbackState.correct:
        gifAsset = 'assets/gifs/correct.gif';
        headerColor = Colors.green;
        break;
      case FeedbackState.wrong:
        gifAsset = 'assets/gifs/wrong.gif';
        headerColor = Colors.red;
        break;
      case FeedbackState.noText:
        gifAsset = 'assets/gifs/confused.gif';
        headerColor = Colors.orange;
        break;
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button at the top right if needed
            if (showCloseButton)
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: onContinue,
                  child: const Icon(
                    Icons.close,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
              ),

            // GIF animation
            SizedBox(
              height: 120,
              width: 120,
              child: Image.asset(
                gifAsset,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),

            // Heading
            Text(
              heading,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: headerColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Message
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF324259),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Continue button
            if (showContinueButton)
              ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: headerColor,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}