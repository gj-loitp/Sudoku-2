import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sudoku/painters.dart';
import 'package:sudoku/stack.dart';

import 'package:sudoku_api/sudoku_api.dart';

import 'fade_dialog.dart';
import 'move.dart';

class SudokuGame extends StatefulWidget {
  final int clues;

  const SudokuGame({Key? key, required this.clues}) : super(key: key);

  @override
  State<SudokuGame> createState() => _SudokuGameState();
}

class _SudokuGameState extends State<SudokuGame> with TickerProviderStateMixin {
  Puzzle? _puzzle;
  Grid? _board;

  final LIFO<Move> _undoStack = LIFO();


  bool _marking = false;
  int _selectedNumber = -1;

  int _validations = 0;
  final List<Position> _validationWrongCells = List.empty(growable: true);

  late List<AnimationController> _scaleAnimationControllers;
  late List<Animation<double>> _scaleAnimations;

  late Timer refreshTimer;
  _SudokuGameState() : super() {
    // refresh the timer every second
    refreshTimer = Timer.periodic(
        const Duration(seconds: 1), (Timer t) => setState(() {}));
  }

  @override
  void initState() {
    super.initState();

    _scaleAnimationControllers = List.generate(9*9, (index) {
      return AnimationController(
          duration: const Duration(milliseconds: 500), vsync: this, value: 0.1);
    });

    _scaleAnimations = List.generate(9*9, (index) {
      return CurvedAnimation(parent: _scaleAnimationControllers[index], curve: Curves.bounceOut);
    });
  }

  @override
  void dispose() {
    super.dispose();

    refreshTimer.cancel();

    for(int i = 0; i < _scaleAnimationControllers.length; i++) {
      _scaleAnimationControllers[i].dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_puzzle == null) {
      _puzzle =
          Puzzle(PuzzleOptions(patternName: "random", clues: widget.clues));

      _puzzle!.generate().then((_) {
        _puzzle!.startStopwatch();

        setState(() {
          _board = _puzzle!.board()!;

          Random rand = Random();

          for(int i = 0; i < _scaleAnimationControllers.length; i++) {
            Future.delayed(Duration(milliseconds: rand.nextInt(500)), () => _scaleAnimationControllers[i].forward());
          }
        });
      });

      /**
       * TODO is it safe to just carry on and access puzzle data,
       * despite it not being generated yet?
       * Dunno about you, but sounds like a recipe for disaster to me.
       */
    }

    const int boardLength = 9;

    String timeString = timeToString(_puzzle!.getTimeElapsed());


    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // dark text for status bar
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                      color: Theme.of(context).textTheme.bodyMedium!.color!,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back)
                  ),
                  Text(timeString, style: Theme.of(context).textTheme.bodyMedium),
                  IconButton( // place secret icon to center text
                    enableFeedback: false,
                    color: Theme.of(context).canvasColor,
                    onPressed: () => {},
                    icon: const Icon(Icons.arrow_forward),
                    splashRadius: 1,
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        margin: const EdgeInsets.all(8.0),
                        child: GridView.builder(
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: boardLength,
                          ),
                          itemBuilder: _buildGridItems,
                          itemCount: boardLength * boardLength,
                          primary: true, // disable scrolling
                          physics: const NeverScrollableScrollPhysics(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Flex(
                        direction: Axis.horizontal,
                        children: [
                          Flexible(
                            flex: 1,
                            child: GridView.builder(
                              shrinkWrap: true,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                              ),
                              itemBuilder: _buildNumberButtons,
                              itemCount: 10,
                              primary: true, // disable scrolling
                              physics: const NeverScrollableScrollPhysics(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 75,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                fadeDialog(context, "Are you sure you want to restart this game?", "Cancel", "Restart", () => {}, () {
                                  setState(() {
                                    _puzzle = null; // cause the board to be re-generated
                                    _selectedNumber = -1;
                                    _validationWrongCells.clear();
                                    _undoStack.clear();
                                  });
                                });
                              },
                              style: ButtonStyle(
                                shape: MaterialStateProperty.all(
                                    RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30.0))),
                              ),
                              child: const Icon(Icons.refresh),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                fadeDialog(context, "Are you sure you want to validate?", "Cancel", "Validate", () => {}, () {
                                  _validations++;

                                  _validationWrongCells.clear();

                                  setState(() {
                                    for (int x = 0; x < 9; x++) {
                                      for (int y = 0; y < 9; y++) {
                                        Cell cell =
                                        _board!.cellAt(Position(row: x, column: y));
                                        if (cell.getValue() != 0 &&
                                            !cell.valid()! &&
                                            !cell.pristine()!) {
                                          _validationWrongCells
                                              .add(Position(row: y, column: x));
                                        }
                                      }
                                    }
                                  });
                                });
                              },
                              style: ButtonStyle(
                                shape: MaterialStateProperty.all(
                                    RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30.0))),
                              ),
                              child: const Icon(Icons.check),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AnimatedContainer(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                color: _marking ? Theme.of(context).primaryColor : Theme.of(context).canvasColor,
                              ),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.ease,
                              child: OutlinedButton(
                                onPressed: () {
                                  // toggle marking mode
                                  setState(() => {_marking = !_marking});
                                },
                                style: ButtonStyle(
                                  backgroundColor: MaterialStateProperty.all(
                                     Colors.transparent),
                                  foregroundColor: MaterialStateProperty.all(_marking
                                      ? Theme.of(context).canvasColor
                                      : Theme.of(context).primaryColor), // TODO should I use textColor for these?
                                  shape: MaterialStateProperty.all(
                                      RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(30.0))),
                                ),
                                child: const Icon(Icons.edit),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                if (_undoStack.isEmpty) {
                                  return;
                                }

                                // undo the move
                                setState(() {
                                  Move move = _undoStack.pop();
                                  Cell cell = _board!
                                      .cellAt(Position(row: move.y, column: move.x));

                                  cell.setValue(move.value);

                                  cell.clearMarkup();
                                  // ignore: avoid_function_literals_in_foreach_calls
                                  move.markup.forEach(
                                      (element) => {cell.addMarkup(element)});
                                });
                              },
                              style: ButtonStyle(
                                shape: MaterialStateProperty.all(
                                    RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30.0))),
                              ),
                              child: const Icon(Icons.undo),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
      ),
    );
  }

  Widget _buildGridItems(BuildContext context, int index) {
    int boardLength = 9;
    int sectorLength = 3;

    int x, y = 0;
    x = (index % boardLength);
    y = (index / boardLength).floor();

    // not my best code...
    Border border = Border(
      right: ((x % sectorLength == sectorLength - 1) && (x != boardLength - 1))
          ? BorderSide(width: 2.0, color: Theme.of(context).indicatorColor)
          : ((x == boardLength - 1)
              ? BorderSide.none
              : BorderSide(width: 1.0, color: Theme.of(context).dividerColor)),
      bottom: ((y % sectorLength == sectorLength - 1) && (y != boardLength - 1))
          ? BorderSide(width: 2.0, color: Theme.of(context).indicatorColor)
          : ((y == boardLength - 1)
              ? BorderSide.none
              : BorderSide(width: 1.0, color: Theme.of(context).dividerColor)),
    );

    return GestureDetector(
      onTap: () {
        Position pos = Position(row: y, column: x);
        Cell cell = _board!.cellAt(pos);

        if (_selectedNumber == -1 ||
            _puzzle!.board() == null ||
            cell.prefill()!) {
          return;
        }

        // place cell
        setState(() {
          _undoStack
              .push(Move(x, y, cell.getValue()!, List.from(cell.getMarkup()!)));

          if (_selectedNumber != 10) {
            if (!_marking && cell.getValue() == _selectedNumber) {
              _puzzle!.fillCell(pos, 0);

              _validationWrongCells.removeWhere(
                  (element) => (x == element.grid!.x && y == element.grid!.y));

            } else {
              if (_marking) {
                if (!cell.markup() ||
                    (!cell.getMarkup()!.contains(_selectedNumber) &&
                        cell.getMarkup()!.length <= 8)) {
                  cell.addMarkup(_selectedNumber);
                } else {
                  cell.removeMarkup(_selectedNumber);
                }

                _puzzle!.fillCell(pos, 0);
              } else {
                cell.clearMarkup();
                _puzzle!.fillCell(pos, _selectedNumber);
              }

              _validationWrongCells.removeWhere(
                  (element) => (x == element.grid!.x && y == element.grid!.y));

              Future<bool> solved = isBoardSolved();
              solved.then((value) {

                if (value) {
                  win(context);
                }
              });
            }
          } else if (!cell.prefill()!) {
            cell.clearMarkup();
            _puzzle!.fillCell(pos, 0);
            _validationWrongCells.removeWhere(
                (element) => (x == element.grid!.x && y == element.grid!.y));
          }
        });
      },
      child: GridTile(
        child: CustomPaint(
          foregroundPainter: EdgePainter(border, x != boardLength - 1, y != boardLength - 1),
          //decoration: BoxDecoration(border: border),
          child: Center(
            child: _buildGridItem(x, y),
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem(int x, int y) {
    if (_board == null) {
      return const SizedBox.shrink();
    }

    Cell cell = _board!.cellAt(Position(column: x, row: y));

    int val = cell.getValue()!;

    if (val == 0 && !cell.markup()) {
      return const SizedBox.shrink();
    } // show nothing for empty cells

    Color textColor = Theme.of(context).textTheme.bodyMedium!.color!;
    Color itemColor = Colors.transparent;

    if(cell.prefill()!) {
      textColor = textColor.withOpacity(0.65);
      itemColor = textColor.withOpacity(0.07);
    }

    bool highlighted = false;

    if (val == _selectedNumber ||
        (cell.markup() && cell.getMarkup()!.contains(_selectedNumber))) {
      itemColor = Theme.of(context).primaryColor;
      highlighted = true;
    }

    if (_validationWrongCells
        .any((element) => ((element.grid!.x == x) && (element.grid!.y == y)))) {
      itemColor = Colors.red; // TODO desaturate
      highlighted = true;
    }

    List<String> markup = List.generate(cell.getMarkup()!.length,
        (index) => cell.getMarkup()!.elementAt(index).toString());



    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ScaleTransition(
        scale: _scaleAnimations[y * 9 + x],
        alignment: Alignment.center,
        child: AnimatedContainer(
          curve: Curves.ease,
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: itemColor, borderRadius: BorderRadius.circular(500)
            //more than 50% of width makes circle
          ),
          child: Center(
            child: cell.markup()
                ? DefaultTextStyle(
                    style: DefaultTextStyle.of(context).style.apply(
                      decoration: TextDecoration.none,
                      color: highlighted
                          ? Theme.of(context).canvasColor
                          : textColor),
                    child: Container(
                      color: Colors.transparent,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: Column(
                          children: [
                            // TODO this is ugly. Is there a better way?
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              // NQSP to preserve small text size
                              children: [
                                Text(markup.length >= 8 ? markup[7] : " "),
                                Text(markup.length >= 7 ? markup[6] : " "),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(markup.length >= 6 ? markup[5] : " "),
                                Text(markup.length >= 5 ? markup[4] : " "),
                                Text(markup.length >= 4 ? markup[3] : " "),
                                Text(markup.length >= 3 ? markup[2] : " "),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(markup.length >= 2 ? markup[1] : " "),
                                Text(markup.length >= 1 ? markup[0] : " "),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.fill,
                    child: Text(
                      val.toString(),
                      style: DefaultTextStyle.of(context).style.apply(
                        color: highlighted ? Theme.of(context).canvasColor : textColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberButtons(BuildContext context, int index) {
    if (_board == null) {
      return const SizedBox.shrink();
    }

    int count = 0;
    for (int x = 0; x < 9; x++) {
      for (int y = 0; y < 9; y++) {
        if (_board!.getColumn(x)[y].getValue() == index + 1) {
          count++;
        }
      }
    }

    String countString = (9 - count).toString();
    if (index == 9 || count == 9) {
      countString = "";
    } else {
      if (count > 9) {
        countString = "${count - 9}+";
      }
    }

    int selectedIndex = _selectedNumber - 1;

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(300),
          color: selectedIndex == index
              ? Theme.of(context).primaryColor
              : Theme.of(context).canvasColor,
        ),
        child: OutlinedButton(
          onPressed: () {
            setState(() {
              if (_selectedNumber == index + 1) {
                _selectedNumber = -1;
              } else {
                _selectedNumber = index + 1;
              }
            });
          },
          style: ButtonStyle(
            shape: MaterialStateProperty.all(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(300.0))),
            backgroundColor: MaterialStateProperty.all(Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(
                flex: 4,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Text(
                    " ", // for spacing
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Text(
                    (index == 9) ? "X" : (index + 1).toString(),
                    style: TextStyle(
                      color: selectedIndex == index
                          ? Theme.of(context).canvasColor
                          : Theme.of(context).textTheme.bodyMedium!.color!,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  countString,
                  style: TextStyle(
                    color: selectedIndex == index
                      ? Theme.of(context).canvasColor
                      : Theme.of(context).textTheme.bodyMedium!.color!,
                  ),
                ),
              ),
              const Expanded(
                flex: 1,
                child: SizedBox.shrink()
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> isBoardSolved() async {
    for (int i = 0; i < 9 * 9; i++) {
      if (_board!.cellAt(Position(index: i)).getValue() == 0) {
        return false;
      }
    }

    for (int x = 0; x < 9; x++) {
      if (_board!.isColumnViolated(Position(column: x, row: 0))) {
        return false;
      }
      if (_board!.isRowViolated(Position(row: x, column: 0))) {
        return false;
      }

      if (_board!.isSegmentViolated(Position(index: x * 9))) {
        return false;
      }
    }

    return true;
  }

  String timeToString(Duration time) {
    String timeString = "";

    if (time.inDays != 0) {
      timeString += "${time.inDays}D ";
    }
    if (time.inHours != 0) {
      timeString += "${time.inHours % 24}H ";
    }
    if (time.inMinutes != 0) {
      timeString += "${time.inMinutes % 60}M ";
    }
    if (time.inSeconds != 0) {
      timeString += "${time.inSeconds % 60}S";
    }

    return timeString;
  }

  void win(BuildContext context) {
    _puzzle!.stopStopwatch();

    List<String> winStrings = ["You win!", "Great job!", "Impressive.", "EYYYYYYYY"];

    int rand = Random().nextInt(winStrings.length);

    fadePopup(context, AlertDialog(
      title: Center(child: Text(winStrings[rand])),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Difficulty: ${widget.clues}"),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Validations used: $_validations"),
            ],
          ),
          Text("Time: ${timeToString(_puzzle!.getTimeElapsed())}"),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16.0, 0, 0),
            child: OutlinedButton(
              onPressed: () {
                // TODO is this a good idea/allowed? How else do I pop twice?

                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ButtonStyle(
                shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0))),
              ),
              child: const Text("Got it!")
            ),
          ),
        ],
      ),
    ));
  }
}
