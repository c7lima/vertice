import { describe, expect, test } from 'vitest';
import { indice, mil, milhoes, num, sim } from './dados';

// O warehouse devolve número como string: estas funções são a defesa das telas.
describe('dados', () => {
  test('num converte o texto do warehouse e não deixa NaN chegar na tela', () => {
    expect(num('6465000.55')).toBe(6465000.55);
    expect(num(null)).toBe(0);
    expect(num('abc')).toBe(0);
  });

  test('o texto "true" também é sim', () => {
    expect(sim('true')).toBe(true);
    expect(sim(true)).toBe(true);
    expect(sim('false')).toBe(false);
  });

  test('a conta do simulador da aula: COL0017 → PRJ-011', () => {
    const ociosidade = num('7530.795') * 4;
    const mobilizacao = 40 * num('199.80');
    expect(mil(ociosidade)).toBe('R$ 30,1 mil');
    expect(mil(mobilizacao)).toBe('R$ 8,0 mil');
    expect(mil(ociosidade - mobilizacao)).toBe('R$ 22,1 mil');
  });

  test('formatos em português', () => {
    expect(milhoes('6465000.55')).toBe('R$ 6,5 mi');
    expect(indice('0.9193758549')).toBe('0,92');
  });
});
