Imagem Armbian Trixie minimal (kernel 6.18) para RK322x, para dar
partida pelo cartão SD e instalar o sistema na NAND.

O workflow baixa a imagem community `Rk322x-box` Trixie current e
acrescenta:

- `rknand.ko`, o driver de NAND da Rockchip ([eloirotava/rknand], a
  partir do porte do [hataketsu/rk322x-s3plus-mainline]), compilado
  contra o kernel da imagem, e o overlay `nand-vendor`, gerado com os
  phandles do DTB da imagem;
- `/root/nand-kit`: a cadeia de boot pela NAND, compilada no próprio
  workflow (`nand-kit/build-uboot.sh`): o U-Boot 2017.09 da Rockchip com
  os dois patches do hataketsu, o trust do `rkbin`, o idblock (DDR +
  miniloader) e o `parameter`;
- `rk-nand-install`, que grava essa cadeia na NAND e copia o sistema do
  SD para lá.

## Uso

1. Grave a imagem num cartão SD e dê partida por ele. Se a NAND tiver
   algo que dê partida (ou que trave), use o jumper que faz a caixa pular
   a NAND.
2. Carregue o driver na mão: `modprobe rknand`. Ele **não** sobe sozinho,
   porque a FTL da Rockchip pode formatar uma NAND que não reconheça.
   Veja o `dmesg` e o `/dev/rknand0`.
3. `rk-nand-install` sem argumentos mostra o que seria feito.
   `rk-nand-install --yes` apaga a NAND, grava idblock, parameter,
   U-Boot e trust, e copia o sistema.
4. Desligue, tire o SD e ligue com o TTL (115200). O U-Boot deve mostrar
   `Bootdev(atags): rknand 0` e carregar o `extlinux` da partição 3.

A partida pela NAND foi provada pelo hataketsu no kernel 6.6. Esta
imagem, com o 6.18, ainda não foi testada em hardware.

[eloirotava/rknand]: https://github.com/eloirotava/rknand
[hataketsu/rk322x-s3plus-mainline]: https://github.com/hataketsu/rk322x-s3plus-mainline
