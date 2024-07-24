REM このファイルは改行コードCRLF、ANSI(Shift-JIS)でなければならない。(そうじゃないと文字化けしたり行頭の文字が欠けて解釈される)
start powershell -WindowStyle Hidden -ExecutionPolicy RemoteSigned -file "%~dp0付属品\PS-Edge_Default.ps1"
