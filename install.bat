@echo off
set /p Credentials=Enter ADMIN credentials:
set /p InstallUser=Enter owner schema for UTL_FTP:
set /p DefLang=Enter default language (Oracle language name) for messages:

set nls_lang=GERMAN_GERMANY.AL32UTF8

sqlplus %Credentials% @utl_ftp/utl_ftp_install.sql %InstallUser% %DefLang%

pause
