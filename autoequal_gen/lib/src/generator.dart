library generator;

import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:autoequal/src/src.dart';
import 'package:autoequal_gen/autoequal_gen.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:equatable/equatable.dart';
import 'package:source_gen/source_gen.dart';

part 'template/extension.dart';
part 'template/mixin.dart';

const _equatable = TypeChecker.fromRuntime(Equatable);
const _equatableMixin = TypeChecker.fromRuntime(EquatableMixin);
const _ignore = TypeChecker.fromRuntime(IgnoreAutoequal);
const _include = TypeChecker.fromRuntime(IncludeAutoequal);

/// For class marked with @Autoequal annotation will be generated properties list List<Object>
/// to use it as value for List<Object> props of Equatable object.
/// If mixin=true so a mixin with overrides 'List<Object> get props' will be additionally generated.
class AutoequalGenerator extends GeneratorForAnnotation<Autoequal> {
  @override
  FutureOr<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    final classElement = _validateElement(element);

    final generated = <String>[];

    final mixin = _generateMixin(classElement, annotation);
    if (mixin != null) {
      generated.add(mixin);
    }

    final extension = _generateExtension(
      classElement,
      includeDeprecated: mixin == null,
    );
    generated.add(extension);

    return generated.join('\n\n');
  }

  String _generateExtension(
    ClassElement classElement, {
    required bool includeDeprecated,
  }) {
    final name = classElement.name;

    final props = classElement.getGetter('props');

    if (classElement.equatableType.isClass && props == null) {
      print('\n[EXT] class "$name" does not have props getter\n');
    }

    final autoEqualFields = classElement.fields
        .where((field) => _isNotIgnoredField(field))
        .map((e) => e.name);

    return _AutoequalExtensionTemplate.generate(
      name,
      autoEqualFields,
      includeDeprecated: includeDeprecated,
    );
  }

  String? _generateMixin(ClassElement classElement, ConstantReader annotation) {
    final isMixin = annotation.read('mixin').boolValue;

    final equatableType = classElement.equatableType;
    if (!equatableType.isMixin) {
      return null;
    }

    final equatableIsSuper = classElement.equatableIsSuper;

    if (equatableIsSuper) {
      final props = classElement.getGetter('props');

      if (props == null) {
        print(
            '\n[MIXIN] class "${classElement.name}" does not have props getter\n');
      }
    }

    if (isMixin || equatableType.isMixin) {
      return _AutoequalMixinTemplate.generate(
        classElement.name,
        equatableType.equatableName!,
      );
    } else {
      return null;
    }
  }

  bool _isNotIgnoredField(FieldElement element) {
    if (element.isStatic) {
      return true;
    }

    if (element.name == 'props') {
      return false;
    }

    if (_ignore.hasAnnotationOfExact(element)) {
      return false;
    }

    if (element.getter == null) {
      return false;
    }

    if (_include.hasAnnotationOfExact(element)) {
      return true;
    }

    if (_ignore.hasAnnotationOfExact(element.getter!)) {
      return false;
    }

    if (_include.hasAnnotationOfExact(element.getter!)) {
      return true;
    }

    if (element.isSynthetic) {
      if (settings.includeGetters) {
        return true;
      }

      return false;
    }

    return true;
  }

  ClassElement _validateElement(Element element) {
    if (element is! ClassElement) {
      throw '$element is not a ClassElement';
    }

    if (!element.usesEquatable) {
      final superIsEquatable = element.equatableIsSuper;

      if (!superIsEquatable) {
        throw 'Class ${element.name} is not a subclass of Equatable or EquatableMixin';
      }
    }

    return element;
  }
}

enum EquatableType {
  class_,
  mixin,
  none,
}

extension on EquatableType {
  bool get isClass => this == EquatableType.class_;
  bool get isMixin => this == EquatableType.mixin;
  bool get isNone => this == EquatableType.none;

  String? get equatableName {
    switch (this) {
      case EquatableType.class_:
        return 'Equatable';
      case EquatableType.mixin:
        return 'EquatableMixin';
      case EquatableType.none:
        return null;
    }
  }
}

extension on ClassElement {
  bool get usesEquatable {
    return !equatableType.isNone;
  }

  bool get equatableIsSuper {
    for (final superType in allSupertypes) {
      final element = superType.element;

      final name = superType.element.name;
      if (name == 'Equatable' ||
          name == 'EquatableMixin' ||
          name.endsWith('AutoequalMixin') ||
          name == 'Object') {
        continue;
      }

      if (!element.equatableType.isNone) {
        return true;
      }
    }

    return false;
  }
}

extension _ElementX on Element {
  bool get isWithEquatableMixin {
    final element = this;

    if (element is! ClassElement) {
      return false;
    }

    if (element.mixins.isEmpty) {
      return false;
    }

    return element.mixins
        .any((type) => _equatableMixin.isExactly(type.element));
  }

  EquatableType get equatableType {
    if (this is! ClassElement) {
      return EquatableType.none;
    }

    if (_equatable.isSuperOf(this)) {
      return EquatableType.class_;
    } else if (isWithEquatableMixin) {
      return EquatableType.mixin;
    } else {
      return EquatableType.none;
    }
  }
}
