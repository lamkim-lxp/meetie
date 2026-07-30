make app
rm -rf build/dmg-root
mkdir -p build/dmg-root
cp -R build/Meetie.app build/dmg-root/
ln -s /Applications build/dmg-root/Applications
hdiutil create \
  -volname "Meetie" \
  -srcfolder build/dmg-root \
  -format UDZO \
  -ov \
  build/Meetie-1.0.dmg
shasum -a 256 build/Meetie-1.0.dmg