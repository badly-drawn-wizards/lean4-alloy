/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Alloy.C.Shim
import Lean.Server.Requests

open Lean Server JsonRpc

namespace Alloy.C

def Shim.leanPosToCLsp? (self : Shim) (leanPos : String.Pos) : Option Lsp.Position := do
  self.text.utf8PosToLspPos (← self.leanPosToShim? leanPos)

def Shim.cLspPosToLean? (self : Shim) (cPos : Lsp.Position) : Option String.Pos := do
  self.shimPosToLean? (self.text.lspPosToUtf8Pos cPos)

def Shim.cPosToLeanLsp? (self : Shim) (cPos : String.Pos) (leanText : FileMap) : Option Lsp.Position := do
  leanText.utf8PosToLspPos (← self.shimPosToLean? cPos)

def Shim.cLspPosToLeanLsp? (self : Shim) (cPos : Lsp.Position) (leanText : FileMap) : Option Lsp.Position := do
  leanText.utf8PosToLspPos (← self.cLspPosToLean? cPos)

/-- Fallback to returning `resp` if `act` errors. Also, log the error message. -/
def withFallbackResponse (resp : RequestTask α) (act : RequestM (RequestTask α)) : RequestM (RequestTask α) :=
  try
    act
  catch e =>
    (←read).hLog.putStrLn s!"C language server request failed: {e.message}"
    return resp

def cRequestError [ToString α] : ResponseError α → RequestError
| {id, code, message, data?} =>
  let data := data?.map (s!"\n{·}") |>.getD ""
  .mk code s!"C language server request {id} failed: {message}{data}"
