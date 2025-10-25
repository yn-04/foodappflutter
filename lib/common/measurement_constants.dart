/// ค่าคงที่สำหรับแปลงหน่วยที่อ้างอิงจากมาตรฐานภายนอกที่ตรวจสอบได้
/// - BIPM, *The International System of Units (SI Brochure, 9th ed.)*, 2019.
///   - ให้ความสัมพันธ์ระหว่างกิโลกรัม-กรัม และลิตร-มิลลิลิตร (คูณ 10^3)
///   - https://www.bipm.org/en/publications/si-brochure
/// - NIST, *Special Publication 811: Guide for the Use of the International System of Units*, 2008.
///   - แปลงออนซ์และปอนด์เป็นกรัม (avoirdupois)
///   - https://www.nist.gov/pml/sp-811
/// - Codex Alimentarius Commission, *Guidelines on Nutrition Labelling* (CXG 2-1985) ภาคผนวก 2.
///   - กำหนดช้อนโต๊ะ 15 มล. และช้อนชา 5 มล. สำหรับงานโภชนาการ
///   - https://www.fao.org/fao-who-codexalimentarius
/// - U.S. FDA, *21 CFR §101.9(b)(5)(viii)*.
///   - ใช้ค่ามาตรฐาน 1 ถ้วย = 240 มล. สำหรับฉลากโภชนาการ
///   - https://www.ecfr.gov/current/title-21/chapter-I/subchapter-B/part-101/section-101.9
class MeasurementConstants {
  static const double gramsPerKilogram = 1000.0;
  static const double millilitersPerLiter = 1000.0;
  static const double milligramsPerGram = 1000.0;
  static const double gramsPerOunce = 28.349523125;
  static const double gramsPerPound = 453.59237;
  static const double millilitersPerTablespoon = 15.0;
  static const double millilitersPerTeaspoon = 5.0;
  static const double millilitersPerCup = 240.0;
  static const double millilitersPerFluidOunceUS = 29.5735295625;
  static const double millilitersPerPintUS = 473.176473;
  static const double millilitersPerQuartUS = 946.352946;
  static const double millilitersPerGallonUS = 3785.411784;
}
