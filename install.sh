#!/bin/bash
echo -n "Enter Connect-String for DBA account [ENTER] "
read SYSPWD
echo ${SYSPWD}

echo -n "Enter owner schema for UTL_FTP [ENTER] "
read OWNER
echo ${OWNER}

echo -n "Enter default language (Oracle language name) [ENTER] "
read DEFAULT_LANGUAGE
echo ${DEFAULT_LANGUAGE}

NLS_LANG=GERMAN_GERMANY.AL32UTF8
export NLS_LANG
sqlplus /nolog<<EOF
connect ${SYSPWD}
@UTL_FTP/utl_ftp_install.sql ${OWNER} ${DEFAULT_LANGUAGE}
pause
EOF

