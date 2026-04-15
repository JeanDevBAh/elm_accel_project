import os
from PIL import Image

def converter_png_para_quartus(caminho_png, bits=8):
    if not os.path.exists(caminho_png):
        print(f"Erro: Arquivo {caminho_png} não encontrado.")
        return

    # Abre a imagem e converte para escala de cinza ('L')
    img = Image.open(caminho_png).convert('L')
    
    # Redimensiona para 28x28 caso a imagem seja maior/menor
    img = img.resize((28, 28))
    
    # Transforma os pixels em uma lista de números (0-255)
    pixels = list(img.getdata())
    
    base_name = os.path.splitext(os.path.basename(caminho_png))[0]
    depth = len(pixels) # Deve ser 784

    # --- GERAR .HEX ---
    with open(f"{base_name}.hex", 'w') as f:
        for p in pixels:
            f.write(f"{p:02X}\n")


    print(f"Sucesso! Imagem '{caminho_png}' convertida para {base_name}.mif e {base_name}.hex")

if __name__ == "__main__":
    pasta_imagens = './9'
    # Converte todas as imagens PNG da pasta
    for arquivo in os.listdir(pasta_imagens):
        if arquivo.endswith(".png"):
            converter_png_para_quartus(os.path.join(pasta_imagens, arquivo))