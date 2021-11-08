require 'spec_helper'

describe Spree::StockItem do
  describe 'sending webhooks' do
    let(:store) { create(:store, default: true) }
    let!(:product) do
      product = create(:product)
      product.master.stock_items.first.update_columns(count_on_hand: 10)
      product
    end
    let(:stock_item) { product.master.stock_items.take }
    let(:body) { Spree::Api::V2::Platform::ProductSerializer.new(product).serializable_hash.to_json }

    describe '#save' do
      context 'when all product variants are tracked' do
        context 'when product total_on_hand is greater than 0' do
          context 'when product is backorderable' do
            before { stock_item.update_column(:backorderable, true) }

            it 'does not emit the product.out_of_stock event' do
              expect { stock_item.adjust_count_on_hand(10) }.not_to emit_webhook_event('product.out_of_stock')
            end
          end

          context 'when product is not backorderable' do
            before { stock_item.update_column(:backorderable, false) }

            it 'does not emit the product.out_of_stock event' do
              expect { stock_item.adjust_count_on_hand(10) }.not_to emit_webhook_event('product.out_of_stock')
            end
          end
        end

        context 'when product total_on_hand is equal to 0' do
          context 'when it is backorderable' do
            it 'does not emit the product.out_of_stock event' do
              expect { stock_item.set_count_on_hand(0) }.not_to emit_webhook_event('product.out_of_stock')
            end
          end

          context 'when it is not backorderable' do
            before { stock_item.update_column(:backorderable, false) }

            it 'emits the product.out_of_stock event' do
              expect { stock_item.set_count_on_hand(0) }.to emit_webhook_event('product.out_of_stock')
            end
          end
        end

        context 'when product total_on_hand is less than 0 and is backorderable' do
          before { stock_item.update_column(:backorderable, true) }

          it 'does not emit the product.out_of_stock event' do
            expect { stock_item.set_count_on_hand(-2) }.not_to emit_webhook_event('product.out_of_stock')
          end
        end
      end

      context 'when some of product variants is not tracked' do
        before do
          stock_item.update_column(:backorderable, false)
          product.master.update(track_inventory: false)
        end

        context 'when product total_on_hand is greater than 0' do
          it 'does not emit the product.out_of_stock event' do
            expect { stock_item.adjust_count_on_hand(10) }.not_to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand is equal to 0' do
          it 'does not emit the product.out_of_stock event' do
            expect { stock_item.adjust_count_on_hand(0) }.not_to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand is less than 0' do
          it 'does not emit the product.out_of_stock event' do
            expect { stock_item.adjust_count_on_hand(-10) }.not_to emit_webhook_event('product.out_of_stock')
          end
        end
      end

      context 'when first stock item is created' do
        let(:other_product) { build(:product, stores: [store]) }

        it 'does not emit the product.out_of_stock event' do
          expect { other_product.save }.not_to emit_webhook_event('product.out_of_stock')
        end
      end

      context 'when count_on_hand did not change' do
        before { stock_item.set_count_on_hand(0) }

        it 'does not emit the product.out_of_stock event' do
          expect { stock_item.update(backorderable: false) }.not_to emit_webhook_event('product.out_of_stock')
        end
      end
    end

    describe '#destroy' do
      context 'when all product variants are tracked' do
        let!(:second_variant) do
          variant = create(:variant, product: product)
          variant.stock_items.take.update_column(:count_on_hand, 10)
          variant
        end

        context 'when product total_on_hand after deleting some stock item is greater than 0' do
          before { stock_item.adjust_count_on_hand(10) }

          it 'does not emit the product.out_of_stock event' do
            expect { Timecop.freeze { second_variant.stock_items.take.destroy } }.not_to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand after deleting some stock item is equal to 0' do
          before do
            stock_item.update_columns(count_on_hand: 0, backorderable: false)
          end

          it 'emits the product.out_of_stock event' do
            expect { Timecop.freeze { second_variant.stock_items.take.destroy } }.to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand after deleting some stock item is less than 0' do
          before do
            stock_item.update_columns(count_on_hand: -5, backorderable: false)
          end

          it 'emits the product.out_of_stock event' do
            expect { Timecop.freeze { second_variant.stock_items.take.destroy } }.to emit_webhook_event('product.out_of_stock')
          end
        end
      end

      context 'when some of product variants is not tracked' do
        let!(:second_variant) do
          variant = create(:variant, product: product)
          variant.stock_items.take.update_column(:count_on_hand, 10)
          variant
        end

        before { product.master.update_column(:track_inventory, false) }

        context 'when product total_on_hand after deleting some stock item is greater than 0' do
          it 'does not emit the product.out_of_stock event' do
            expect { second_variant.stock_items.take.destroy }.not_to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand after deleting some stock item is equal to 0' do
          before { stock_item.set_count_on_hand(0) }

          it 'does not emit the product.out_of_stock event' do
            expect { second_variant.stock_items.take.destroy }.not_to emit_webhook_event('product.out_of_stock')
          end
        end

        context 'when product total_on_hand after deleting some stock item is less than 0' do
          before do
            stock_item.update_column(:backorderable, true)
            stock_item.set_count_on_hand(-5)
          end

          it 'does not emit the product.out_of_stock event' do
            expect { second_variant.stock_items.take.destroy }.not_to emit_webhook_event('product.out_of_stock')
          end
        end
      end

      context 'when there are no stock items left' do
        it 'emits the product.out_of_stock event' do
          expect { stock_item.destroy }.to emit_webhook_event('product.out_of_stock')
        end
      end
    end
  end
end
