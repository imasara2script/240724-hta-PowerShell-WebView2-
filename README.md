# PS-Edge_Default
PowerShell + XAML + WebView2 を利用したい人向けのテンプレートファイル群。

# ライセンス
MIT ライセンス

# 環境
下記環境にて動作確認済み。

* Windows 10 Pro 21H2
* Windows 11 Home 21H2

# 準備
init.bat を起動する。

# 利用方法
準備を行った後 boot.bat を起動する。

# 構成ファイル
「data」フォルダはboot.bat実行の度に自動的に作成される。削除してもOK。

「lib」フォルダ内にはwebView2のランタイムDLLを保存する。
「init.bat」を実行すると自動的に最新のDLLに置き換わる筈だが、web上のランタイムパッケージ内のフォルダ構成が変わっていてエラーになってしまう場合は手動で各DLLを上記フォルダにコピー(or移動)する必要がある。
