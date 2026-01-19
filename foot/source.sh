chmod +x theme.py
sudo cp ./theme.py /usr/local/bin/theme

mkdir -p $HOME/.config/foot/themes
cp -rf ./themes/* $HOME/.config/foot/themes
