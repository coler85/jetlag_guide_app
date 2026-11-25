import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'schedule_parser_service.dart';

/// Gallery images go through [ImagePicker]. PDF and other files go through
/// [FilePicker]. Both return the same ref the parser accepts.
class ScheduleFilePicker {
  const ScheduleFilePicker({this.images, this.readImage, this.readDocument});

  final ImagePicker? images;

  /// Test seam. When set, [pickImage] does not open the gallery.
  final Future<ScheduleFileRef?> Function()? readImage;

  /// Test seam. When set, [pickDocument] does not open the system picker.
  final Future<ScheduleFileRef?> Function()? readDocument;

  Future<ScheduleFileRef?> pickImage() async {
    final override = readImage;
    if (override != null) return override();
    final image = await (images ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
    );
    if (image == null) return null;
    return ScheduleFileRef(
      name: image.name,
      path: image.path,
      kind: ScheduleFileKind.image,
    );
  }

  Future<ScheduleFileRef?> pickDocument() async {
    final override = readDocument;
    if (override != null) return override();
    final file = await FilePicker.pickFile(
      dialogTitle: '스케줄 PDF 또는 이미지',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic'],
    );
    if (file == null) return null;
    final extension = (file.extension ?? '').toLowerCase();
    return ScheduleFileRef(
      name: file.name,
      path: file.path,
      kind: extension == 'pdf' ? ScheduleFileKind.pdf : ScheduleFileKind.image,
    );
  }
}
