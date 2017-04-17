// Copyright (c) 2017, Herman Bergwerf. All rights reserved.
// Use of this source code is governed by an AGPL-3.0-style license
// that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_route/shelf_route.dart';
import 'package:json_object/json_object.dart';

import 'package:http/http.dart' as http;

import 'pages/home.dart';
import 'pages/locale.dart';
import 'pages/descriptor.dart';
import 'pages/subject.dart';
import 'pages/translation.dart';
import 'pages/category.dart';
import 'pages/function.dart';
import 'pages/definition.dart';
import 'pages/lineage.dart';

import 'pages/templates.dart';
import 'page.dart';

/// All pages
Map<String, Page> pages = {
  '/': homePage,
  '/locale/create': createLocalePage,
  '/descriptor/create': createDescriptorPage,
  '/descriptor/list': listDescriptorsPage,
  '/descriptor/{id}/read': readDescriptorPage,
  '/descriptor/{id}/translation/create': createTranslationPage,
  '/subject/create': createSubjectPage,
  '/subject/list': listSubjectsPage,
  '/category/create': createCategoryPage,
  '/category/list': listCategoriesPage,
  '/category/{id}/read': readCategoryPage,
  '/category/{id}/category/create': createCategoryPage,
  '/category/{id}/category/list': listSubCategoriesPage,
  '/function/create': createFunctionPage,
  '/function/list': listFunctionsPage,
  '/definition/create': createDefinitionPage,
  '/definition/list': listDefinitionsPage,
  '/lineage/create': createLineagePage,
  '/lineage/list': listLineagesPage,
  '/lineage/{id}/read': readLineagePage
};

Future<Null> setupRouter(String apiBase, Router router) async {
  // Read settings file.
  final settings = loadYaml(await new File('web/settings.yaml').readAsString());

  // Read all snippets.
  final entities = await new Directory('web/snippets').list().toList();
  final snippets = new Map<String, String>();
  for (final entity in entities) {
    final file = new File.fromUri(entity.uri);
    if (await file.exists()) {
      snippets[file.path.split('/').last] = await file.readAsString();
    }
  }

  // Make sure breadcrumb only points to existing pages.
  breadcrumbAvailableLinks.addAll(pages.keys);

  // Serve favicon.
  final faviconData = new File('web/favicon.ico').readAsBytesSync();
  router.get('/favicon.ico', (_) {
    return new Response.ok(faviconData,
        headers: {'Content-Type': 'image/x-icon'});
  });

  // Add handlers for all pages.
  pages.forEach((path, page) {
    router.add(path, ['GET', 'POST'], (Request request) async {
      final data = new PageSessionData(settings, snippets);
      data.path = request.requestedUri.path.split('/');
      data.path.removeWhere((str) => str.isEmpty);
      data.pathParameters = getPathParameters(request);

      if (data.path.isEmpty) {
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      }

      // Load additional resources.
      for (final label in page.additional.keys) {
        final response = await http.get('$apiBase${page.additional[label]}');
        data.additional[label] = new JsonObject.fromJsonString(response.body);
      }

      if (request.method == 'POST' && page.onPost != null) {
        // Decode form data.
        final uri = new Uri(query: await request.readAsString());

        // Encode post data.
        data.request = page.onPost(uri.queryParameters);

        // Get API response.
        final response = await http.post(
            '$apiBase${request.requestedUri.path.substring(1)}',
            headers: {'Content-Type': 'application/json'},
            body: JSON.encode(data.request));
        data.data = new JsonObject.fromJsonString(response.body);

        // Render page.
        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      } else {
        data.data = new JsonObject();

        // Do GET request if no postFormat is specified.
        if (page.onPost == null) {
          final response = await http
              .get('$apiBase${request.requestedUri.path.substring(1)}');
          data.data = new JsonObject.fromJsonString(response.body);
        }

        return new Response.ok(page.template(data),
            headers: {'Content-Type': 'text/html'});
      }
    });
  });
}
