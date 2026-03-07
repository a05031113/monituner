# VP32UQ HDMI DDC 修復計畫

## 根本原因

`Arm64DDC.swift` 的 DDC/CI 封包格式錯誤：opcode 被放進 `send` 陣列，導致框架產生
`[0x83, 0x02, ...]` 而非正確的 `[0x82, 0x01, ...]`。顯示器收到無效 opcode (0x02 = Reply)
而非正確的 request opcode (0x01 = Get VCP / 0x03 = Set VCP)。

## 修復步驟

- [x] 1. 修正 `getVCP()` 封包格式
  - 改為標準 DDC/CI: `[0x82, 0x01, code, checksum]`
  - offset = 0x51, chipAddress = 0x37

- [x] 2. 修正 `setVCP()` 封包格式
  - 改為標準 DDC/CI: `[0x84, 0x03, code, valueHigh, valueLow, checksum]`
  - offset = 0x51, chipAddress = 0x37

- [x] 3. 保留 retry 邏輯（4 retries × 2 write cycles）

- [x] 4. 保留 `DCPAVServiceProxy` + `Location="External"` 服務發現

- [x] 5. 建置並部署到 ~/Applications/MoniTuner.app

- [ ] 6. 測試驗證
  - [ ] VP32UQ (HDMI): 讀取亮度
  - [ ] VP32UQ (HDMI): 設定亮度
  - [ ] BenQ BL3290QT (USB-C): 確認未 regression
  - [ ] 快捷鍵 ⌃F1/⌃F2 兩個螢幕都能控制

- [ ] 7. 清理 MediaKeyTap.swift 中的 debug logging（確認一切正常後）
