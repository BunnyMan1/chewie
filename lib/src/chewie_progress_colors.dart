import 'package:flutter/rendering.dart';

class ChewieProgressColors {
  ChewieProgressColors({
    Color playedColor = const Color(0xFF0B6FE4),
    Color bufferedColor = const Color.fromRGBO(30, 30, 200, 0.2),
    Color handleColor = const Color.fromRGBO(200, 200, 200, 1.0),
    Color backgroundColor = const Color.fromRGBO(200, 200, 200, 0.5),
  }) : playedPaint = Paint()..color = playedColor,
       bufferedPaint = Paint()..color = bufferedColor,
       handlePaint = Paint()..color = handleColor,
       backgroundPaint = Paint()..color = backgroundColor;

  final Paint playedPaint;
  final Paint bufferedPaint;
  final Paint handlePaint;
  final Paint backgroundPaint;
}
