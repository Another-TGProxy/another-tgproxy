; SPDX-License-Identifier: GPL-3.0-or-later
; Portable launcher: a single .exe that, on double-click, unpacks the runtime
; once into a per-user cache and starts the app — no installer, no UI, no
; shortcuts, no registry. Driven from bundle-windows.sh.
Unicode true
SilentInstall silent
RequestExecutionLevel user

!define APPNAME "Another TGProxy"
Name "${APPNAME} ${VERSION}"
OutFile "${OUTFILE}"

!include "LogicLib.nsh"

Section
  ; Cache per version so launches after the first skip extraction and are instant.
  StrCpy $INSTDIR "$LOCALAPPDATA\AnotherTGProxy\runtime\${VERSION}"
  ${IfNot} ${FileExists} "$INSTDIR\bin\another-tgproxy.exe"
    SetOutPath "$INSTDIR"
    File /r "${SRCDIR}\*.*"
  ${EndIf}
  ; cwd in bin so the GTK runtime DLLs resolve; Exec returns immediately.
  SetOutPath "$INSTDIR\bin"
  Exec '"$INSTDIR\bin\another-tgproxy.exe"'
SectionEnd
