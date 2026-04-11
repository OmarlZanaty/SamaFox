import 'dart:math';
import 'package:flutter/material.dart';
import 'simple_bet_game_screen.dart';

class GamesScreens {
  static Widget uefa() => SimpleBetGameScreen(
    title: "UEFA (Quick Pick)",
    icon: Icons.sports_soccer,
    choices: const ["Team A", "Draw", "Team B"],
    resolve: (rng, bet, choice) {
      // 0=A,1=Draw,2=B (draw is rare)
      final roll = rng.nextInt(100);
      final outcomeIndex = (roll < 45) ? 0 : (roll < 55) ? 1 : 2;
      final outcome = ["Team A", "Draw", "Team B"][outcomeIndex];

      final odds = {"Team A": 2, "Draw": 6, "Team B": 2}; // simple odds
      final win = outcome == choice;
      final payout = win ? bet * (odds[choice]!.toInt() - 1) : 0;

      return RoundResult(
        win: win,
        payout: payout,
        outcomeText: "Outcome: $outcome",
      );
    },
  );

  static Widget greedyStar() => SimpleBetGameScreen(
    title: "GreedyStar",
    icon: Icons.star,
    choices: const ["Gold", "Purple", "Pink"],
    resolve: (rng, bet, choice) {
      final outcome = ["Gold", "Purple", "Pink"][rng.nextInt(3)];
      final win = outcome == choice;
      final payout = win ? bet * 2 : 0; // 3x return total (bet+2*bet)
      return RoundResult(win: win, payout: payout, outcomeText: "Star: $outcome");
    },
  );

  static Widget greedyCat() => SimpleBetGameScreen(
    title: "GreedyCat",
    icon: Icons.pets,
    choices: const ["Door 1", "Door 2", "Door 3"],
    resolve: (rng, bet, choice) {
      final outcome = ["Door 1", "Door 2", "Door 3"][rng.nextInt(3)];
      final win = outcome == choice;
      final payout = win ? bet * 2 : 0;
      return RoundResult(win: win, payout: payout, outcomeText: "Cat was in: $outcome");
    },
  );

  static Widget crash() => SimpleBetGameScreen(
    title: "Crash (Instant)",
    icon: Icons.rocket_launch,
    choices: const ["Cashout @1.5x", "Cashout @2x", "Cashout @3x"],
    resolve: (rng, bet, choice) {
      // Crash point between 1.0 and 5.0
      final crashPoint = 1.0 + rng.nextDouble() * 4.0;
      final target = choice.contains("1.5") ? 1.5 : choice.contains("2") ? 2.0 : 3.0;

      final win = crashPoint >= target;
      final payout = win ? (bet * (target - 1)).round() : 0;

      return RoundResult(
        win: win,
        payout: payout,
        outcomeText: "Crash @ ${crashPoint.toStringAsFixed(2)}x",
      );
    },
  );

  static Widget jackpot() => SimpleBetGameScreen(
    title: "Jackpot (Pick a Number)",
    icon: Icons.casino,
    choices: const ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"],
    resolve: (rng, bet, choice) {
      final outcome = (rng.nextInt(10) + 1).toString();
      final win = outcome == choice;
      final payout = win ? bet * 9 : 0; // 10x total return
      return RoundResult(win: win, payout: payout, outcomeText: "Number: $outcome");
    },
  );

  static Widget fishing() => SimpleBetGameScreen(
    title: "Fishing (Quick Catch)",
    icon: Icons.phishing,
    choices: const ["Cast (Small)", "Cast (Medium)", "Cast (Big)"],
    resolve: (rng, bet, choice) {
      // "Bigger" casts have higher payout but lower chance
      final config = {
        "Cast (Small)": (chance: 65, mult: 1.3),
        "Cast (Medium)": (chance: 40, mult: 2.0),
        "Cast (Big)": (chance: 20, mult: 4.0),
      }[choice]!;

      final roll = rng.nextInt(100) + 1;
      final win = roll <= config.chance;
      final payout = win ? max(1, (bet * (config.mult - 1)).round()) : 0;

      return RoundResult(
        win: win,
        payout: payout,
        outcomeText: win ? "You caught a fish! (+${(config.mult).toStringAsFixed(1)}x total)" : "No fish this time.",
      );
    },
  );

  static Widget greedyDice() => SimpleBetGameScreen(
    title: "Greedy Dice (Quick)",
    icon: Icons.casino_outlined,
    choices: const ["Sum 2-6", "Sum 7", "Sum 8-12"],
    resolve: (rng, bet, choice) {
      final d1 = rng.nextInt(6) + 1;
      final d2 = rng.nextInt(6) + 1;
      final sum = d1 + d2;

      String bucket;
      if (sum <= 6) bucket = "Sum 2-6";
      else if (sum == 7) bucket = "Sum 7";
      else bucket = "Sum 8-12";

      final odds = {"Sum 2-6": 2, "Sum 7": 4, "Sum 8-12": 2};
      final win = bucket == choice;
      final payout = win ? bet * (odds[choice]!.toInt() - 1) : 0;

      return RoundResult(win: win, payout: payout, outcomeText: "Dice: $d1 + $d2 = $sum");
    },
  );

  static Widget lionOrTiger() => SimpleBetGameScreen(
    title: "Lion or Tiger",
    icon: Icons.pets_outlined,
    choices: const ["Lion", "Tiger"],
    resolve: (rng, bet, choice) {
      final outcome = rng.nextBool() ? "Lion" : "Tiger";
      final win = outcome == choice;
      final payout = win ? bet : 0; // 2x total return
      return RoundResult(win: win, payout: payout, outcomeText: "Result: $outcome");
    },
  );

  static Widget roulette() => SimpleBetGameScreen(
    title: "Roulette (Simple)",
    icon: Icons.album,
    choices: const ["Red", "Black", "Green"],
    resolve: (rng, bet, choice) {
      // 0..36; green on 0 only
      final number = rng.nextInt(37);
      final outcome = (number == 0)
          ? "Green"
          : (number % 2 == 0)
          ? "Black"
          : "Red";

      final odds = {"Red": 2, "Black": 2, "Green": 14};
      final win = outcome == choice;
      final payout = win ? bet * (odds[choice]!.toInt() - 1) : 0;

      return RoundResult(win: win, payout: payout, outcomeText: "Number: $number ($outcome)");
    },
  );
}
