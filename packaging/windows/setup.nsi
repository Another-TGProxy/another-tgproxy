; SPDX-License-Identifier: GPL-3.0-or-later
; Installer for Another TGProxy. Driven from bundle-windows.sh:
;   makensis -DVERSION=.. -DSRCDIR=..(staged tree) -DICON=..(app .ico) -DOUTFILE=..
Unicode true

!define APPNAME "Another TGProxy"
!define COMPANY "Ampernic"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AnotherTGProxy"

Name "${APPNAME} ${VERSION}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\AnotherTGProxy"
InstallDirRegKey HKLM "Software\AnotherTGProxy" "InstallDir"
RequestExecutionLevel admin
ShowInstDetails show
ShowUninstDetails show

!include "MUI2.nsh"
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\bin\another-tgproxy.exe"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
; English first = fallback for unmatched systems; MUI auto-selects by the user's
; system UI language at runtime, so a Russian Windows gets the Russian installer.
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SRCDIR}\*.*"

  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\bin\another-tgproxy.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\bin\another-tgproxy.exe"

  WriteRegStr HKLM "Software\AnotherTGProxy" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${COMPANY}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\bin\another-tgproxy.exe"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\AnotherTGProxy"
SectionEnd
