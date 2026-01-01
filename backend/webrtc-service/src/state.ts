class InMemoryDurableStorage implements DurableObjectStorage {
  private store = new Map<string, any>();

  async get(key: string | string[]) {
    if (Array.isArray(key)) {
      return Object.fromEntries(key.map((k) => [k, this.store.get(k)]));
    }
    return this.store.get(key);
  }

  async put(key: string | Record<string, any>, value?: any) {
    if (typeof key === 'string') {
      this.store.set(key, value);
      return;
    }
    for (const [k, v] of Object.entries(key)) {
      this.store.set(k, v);
    }
  }

  async delete(key: string | string[]) {
    if (Array.isArray(key)) {
      for (const k of key) {
        this.store.delete(k);
      }
    } else {
      this.store.delete(key);
    }
  }
}

export class MemoryDurableObjectState implements DurableObjectState {
  storage = new InMemoryDurableStorage();
}

export const sharedDurableState = new MemoryDurableObjectState();
