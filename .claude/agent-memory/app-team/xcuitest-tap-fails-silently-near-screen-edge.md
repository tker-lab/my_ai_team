---
name: xcuitest-tap-fails-silently-near-screen-edge
description: SwiftUIのForm/List内でscrollUntilVisible(存在確認のみ)が真を返しても、要素が画面下端ギリギリだとtap()が反応しないことがある
metadata:
  type: project
---

PhotoTimerのUIテストで使っている `scrollUntilVisible`(`element.waitForExistence`だけを見て
スクロールを止める既存ヘルパー)は、要素が**存在してさえいれば**画面のちょうど下端ギリギリ
(ホームインジケータに近い位置)にあっても真を返して止まってしまう。その状態で`.tap()`しても、
座標的に反応しない(スクリーンショットで見えているのに何も起きない)ことがある
(2026-09-06、課金機能のロック表示行のタップで発覚)。

**How to apply:** 新しくスクロールして見つけた要素をタップする時、特にForm/Listの一番下
付近にある行は、存在確認だけでなく`element.frame`(実際の座標)を見て、画面下端から
十分な余白(PhotoTimerでは40pt)があるかまで確認してから叩く。専用の
`scrollUntilTappable`ヘルパー(既存の`scrollUntilVisible`とは別に追加、既存呼び出しは
非破壊)をPhotoTimerUITests.swiftに用意した。他アプリのXCUITestでも、Form/Listの末尾要素の
タップが「見えているのに反応しない」時はこのパターンを疑うとよい。
