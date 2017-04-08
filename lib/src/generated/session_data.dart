// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb.schema;

// PLEASE DO NOT EDIT THIS FILE, THIS CODE IS AUTO-GENERATED.

class SessionData {
  Map<int, DescriptorRow> descriptorTable = {};
  Map<int, SubjectRow> subjectTable = {};
  Map<int, LocaleRow> localeTable = {};
  Map<int, TranslationRow> translationTable = {};
  Map<int, CategoryRow> categoryTable = {};
  Map<int, FunctionRow> functionTable = {};
  Map<int, FunctionSubjectTagRow> functionSubjectTagTable = {};
  Map<int, OperatorRow> operatorTable = {};
  Map<int, ExpressionRow> expressionTable = {};
  Map<int, LineageStepRow> lineageStepTable = {};
  Map<int, RuleRow> ruleTable = {};
  Map<int, DefinitionRow> definitionTable = {};
}
