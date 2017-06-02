// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of qedb.schema;

// PLEASE DO NOT EDIT THIS FILE, THIS CODE IS AUTO-GENERATED.

class SessionData {
  Map<int, DescriptorRow> descriptorTable = {};
  Map<int, SubjectRow> subjectTable = {};
  Map<int, LanguageRow> languageTable = {};
  Map<int, TranslationRow> translationTable = {};
  Map<int, FunctionRow> functionTable = {};
  Map<int, OperatorRow> operatorTable = {};
  Map<int, ExpressionRow> expressionTable = {};
  Map<int, RuleRow> ruleTable = {};
  Map<int, StepRow> stepTable = {};
  Map<int, ProofRow> proofTable = {};
}
