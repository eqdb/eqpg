// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqdb.schema;

// PLEASE DO NOT EDIT THIS FILE, THIS CODE IS AUTO-GENERATED.

final descriptor = new TableInfo<DescriptorRow, SessionData>(
    'descriptor',
    DescriptorRow.mapFormat,
    DescriptorRow.map,
    (result, record) => result.descriptorTable[record.id] = record);
final subject = new TableInfo<SubjectRow, SessionData>(
    'subject',
    SubjectRow.mapFormat,
    SubjectRow.map,
    (result, record) => result.subjectTable[record.id] = record);
final locale = new TableInfo<LocaleRow, SessionData>(
    'locale',
    LocaleRow.mapFormat,
    LocaleRow.map,
    (result, record) => result.localeTable[record.id] = record);
final translation = new TableInfo<TranslationRow, SessionData>(
    'translation',
    TranslationRow.mapFormat,
    TranslationRow.map,
    (result, record) => result.translationTable[record.id] = record);
final category = new TableInfo<CategoryRow, SessionData>(
    'category',
    CategoryRow.mapFormat,
    CategoryRow.map,
    (result, record) => result.categoryTable[record.id] = record);
final function = new TableInfo<FunctionRow, SessionData>(
    'function',
    FunctionRow.mapFormat,
    FunctionRow.map,
    (result, record) => result.functionTable[record.id] = record);
final functionSubjectTag = new TableInfo<FunctionSubjectTagRow, SessionData>(
    'function_subject_tag',
    FunctionSubjectTagRow.mapFormat,
    FunctionSubjectTagRow.map,
    (result, record) => result.functionSubjectTagTable[record.id] = record);
final operator = new TableInfo<OperatorRow, SessionData>(
    'operator',
    OperatorRow.mapFormat,
    OperatorRow.map,
    (result, record) => result.operatorTable[record.id] = record);
final expression = new TableInfo<ExpressionRow, SessionData>(
    'expression',
    ExpressionRow.mapFormat,
    ExpressionRow.map,
    (result, record) => result.expressionTable[record.id] = record);
final lineageStep = new TableInfo<LineageStepRow, SessionData>(
    'lineage_step',
    LineageStepRow.mapFormat,
    LineageStepRow.map,
    (result, record) => result.lineageStepTable[record.id] = record);
final rule = new TableInfo<RuleRow, SessionData>('rule', RuleRow.mapFormat,
    RuleRow.map, (result, record) => result.ruleTable[record.id] = record);
final definition = new TableInfo<DefinitionRow, SessionData>(
    'definition',
    DefinitionRow.mapFormat,
    DefinitionRow.map,
    (result, record) => result.definitionTable[record.id] = record);
