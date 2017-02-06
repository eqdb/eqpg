// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

part of eqpg.dbutils;

// PLEASE DO NOT EDIT THIS FILE, THIS CODE IS AUTO-GENERATED.

final descriptorHelper = new TableHelper<db.DescriptorTable>(
    'descriptor',
    db.DescriptorTable.mapFormat,
    db.DescriptorTable.map,
    (result, record) => result.descriptors.add(record));
final subjectHelper = new TableHelper<db.SubjectTable>(
    'subject',
    db.SubjectTable.mapFormat,
    db.SubjectTable.map,
    (result, record) => result.subjects.add(record));
final localeHelper = new TableHelper<db.LocaleTable>(
    'locale',
    db.LocaleTable.mapFormat,
    db.LocaleTable.map,
    (result, record) => result.locales.add(record));
final translationHelper = new TableHelper<db.TranslationTable>(
    'translation',
    db.TranslationTable.mapFormat,
    db.TranslationTable.map,
    (result, record) => result.translations.add(record));
final categoryHelper = new TableHelper<db.CategoryTable>(
    'category',
    db.CategoryTable.mapFormat,
    db.CategoryTable.map,
    (result, record) => result.categories.add(record));
final functionHelper = new TableHelper<db.FunctionTable>(
    'function',
    db.FunctionTable.mapFormat,
    db.FunctionTable.map,
    (result, record) => result.functions.add(record));
final functionSubjectTagHelper = new TableHelper<db.FunctionSubjectTagTable>(
    'function_subject_tag',
    db.FunctionSubjectTagTable.mapFormat,
    db.FunctionSubjectTagTable.map,
    (result, record) => result.functionSubjectTags.add(record));
final operatorConfigurationHelper =
    new TableHelper<db.OperatorConfigurationTable>(
        'operator_configuration',
        db.OperatorConfigurationTable.mapFormat,
        db.OperatorConfigurationTable.map,
        (result, record) => result.operatorConfigurations.add(record));
final expressionHelper = new TableHelper<db.ExpressionTable>(
    'expression',
    db.ExpressionTable.mapFormat,
    db.ExpressionTable.map,
    (result, record) => result.expressions.add(record));
final functionReferenceHelper = new TableHelper<db.FunctionReferenceTable>(
    'function_reference',
    db.FunctionReferenceTable.mapFormat,
    db.FunctionReferenceTable.map,
    (result, record) => result.functionReferences.add(record));
final integerReferenceHelper = new TableHelper<db.IntegerReferenceTable>(
    'integer_reference',
    db.IntegerReferenceTable.mapFormat,
    db.IntegerReferenceTable.map,
    (result, record) => result.integerReferences.add(record));
final lineageHelper = new TableHelper<db.LineageTable>(
    'lineage',
    db.LineageTable.mapFormat,
    db.LineageTable.map,
    (result, record) => result.lineages.add(record));
final ruleHelper = new TableHelper<db.RuleTable>('rule', db.RuleTable.mapFormat,
    db.RuleTable.map, (result, record) => result.rules.add(record));
final definitionHelper = new TableHelper<db.DefinitionTable>(
    'definition',
    db.DefinitionTable.mapFormat,
    db.DefinitionTable.map,
    (result, record) => result.definitions.add(record));
