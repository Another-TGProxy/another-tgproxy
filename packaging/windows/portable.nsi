; SPDX-License-Identifier: GPL-3.0-or-later
; Portable self-extractor for Another TGProxy: unpacks the runtime to a chosen
; folder (no install, no registry, no shortcuts) and offers to run it.
Unicode true

!define APPNAME "Another TGProxy"

Name "${APPNAME} ${VERSION} (Portable)"
OutFile "${OUTFILE}"
InstallDir "$EXEDIR\AnotherTGProxy"
RequestExecutionLevel user
ShowInstDetails show

!include "MUI2.nsh"
!define MUI_ICON "${ICON}"
!define MUI_DIRECTORYPAGE_TEXT_TOP "Choose a folder to unpack the portable app into."
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\another-tgproxy.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Section
  SetOutPath "$INSTDIR"
  File /r "${SRCDIR}\*.*"
SectionEnd
